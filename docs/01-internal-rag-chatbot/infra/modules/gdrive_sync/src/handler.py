"""Google Drive -> S3 同期Lambda。

サービスアカウント（ドメイン全体委譲、`drive.readonly`スコープ）でGoogle Drive APIに
認証し、SSM Parameter Storeで指定された対象フォルダ配下のファイルをS3バケット
（Knowledge Baseデータソース）へ同期する。同期頻度はPoC初期は手動実行
（requirements.md確定）で、このLambdaを直接invokeする運用を想定する。

環境変数:
  KB_BUCKET_NAME               同期先S3バケット名
  GDRIVE_SECRET_ARN            サービスアカウントJSONキーのSecrets Manager ARN
  GDRIVE_FOLDER_ID_SSM         同期対象フォルダIDのSSM Parameter名
  GDRIVE_IMPERSONATE_USER_SSM  ドメイン全体委譲でなりすます対象ユーザー
                                （フォルダ所有者のメールアドレス）のSSM Parameter名

スコープ外（既知の制約。infra/README.md「既知の構成リスク・要判断事項」参照）:
  - 文書内容のPIIマスキング・文書ごとのアクセス範囲タグ付けは本Lambdaでは未実装。
    requirements.mdでは同期処理をその実施場所として想定していたが、Phase Bの
    最初のステップ（B-1）ではまず同期そのものを動かすことを優先し、別途対応する。
    Guardrails側の出力時マスキング・Contextual grounding checkが一次緩和策となる。
"""

import io
import json
import logging
import os

import boto3
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseDownload

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SCOPES = ["https://www.googleapis.com/auth/drive.readonly"]

# Google純正フォーマット（Google Docs/Sheets/Slides）はバイナリとして直接ダウンロードできず、
# Google Drive APIのexport機能で別形式に変換する必要がある。Knowledge Baseが取り込める
# 形式としてPDFを選択する。
GOOGLE_NATIVE_EXPORT_MIME_TYPES = {
    "application/vnd.google-apps.document": ("application/pdf", ".pdf"),
    "application/vnd.google-apps.spreadsheet": ("application/pdf", ".pdf"),
    "application/vnd.google-apps.presentation": ("application/pdf", ".pdf"),
}

# 同期対象外（フォルダは再帰探索側で処理、ショートカット/フォーム等はKnowledge Base取り込み対象外）
SKIP_MIME_TYPES = {
    "application/vnd.google-apps.shortcut",
    "application/vnd.google-apps.form",
}

s3 = boto3.client("s3")
secretsmanager = boto3.client("secretsmanager")
ssm = boto3.client("ssm")

KB_BUCKET_NAME = os.environ["KB_BUCKET_NAME"]
GDRIVE_SECRET_ARN = os.environ["GDRIVE_SECRET_ARN"]
GDRIVE_FOLDER_ID_SSM = os.environ["GDRIVE_FOLDER_ID_SSM"]
GDRIVE_IMPERSONATE_USER_SSM = os.environ["GDRIVE_IMPERSONATE_USER_SSM"]


def _build_drive_service():
    secret_value = secretsmanager.get_secret_value(SecretId=GDRIVE_SECRET_ARN)
    service_account_info = json.loads(secret_value["SecretString"])

    impersonate_user = ssm.get_parameter(Name=GDRIVE_IMPERSONATE_USER_SSM)["Parameter"]["Value"]

    credentials = service_account.Credentials.from_service_account_info(
        service_account_info, scopes=SCOPES
    ).with_subject(impersonate_user)

    return build("drive", "v3", credentials=credentials, cache_discovery=False)


def _list_files_recursive(drive_service, folder_id, path_prefix=""):
    """folder_id配下のファイルを(Driveファイルメタデータ, S3キー用相対パス)のリストで返す。

    サブフォルダは再帰的に辿り、S3キーにはDrive上のフォルダ階層をそのまま反映する。
    """
    files = []
    page_token = None
    while True:
        response = (
            drive_service.files()
            .list(
                q=f"'{folder_id}' in parents and trashed = false",
                fields="nextPageToken, files(id, name, mimeType, modifiedTime)",
                pageToken=page_token,
                supportsAllDrives=True,
                includeItemsFromAllDrives=True,
            )
            .execute()
        )
        for item in response.get("files", []):
            if item["mimeType"] == "application/vnd.google-apps.folder":
                files.extend(
                    _list_files_recursive(drive_service, item["id"], f"{path_prefix}{item['name']}/")
                )
            elif item["mimeType"] in SKIP_MIME_TYPES:
                continue
            else:
                files.append((item, f"{path_prefix}{item['name']}"))
        page_token = response.get("nextPageToken")
        if not page_token:
            break
    return files


def _download_file(drive_service, file_meta):
    """1ファイル分の内容をバイト列で取得する。Google純正フォーマットはPDFにエクスポートする。"""
    mime_type = file_meta["mimeType"]
    if mime_type in GOOGLE_NATIVE_EXPORT_MIME_TYPES:
        export_mime_type, _ext = GOOGLE_NATIVE_EXPORT_MIME_TYPES[mime_type]
        request = drive_service.files().export_media(fileId=file_meta["id"], mimeType=export_mime_type)
    else:
        request = drive_service.files().get_media(fileId=file_meta["id"], supportsAllDrives=True)

    buffer = io.BytesIO()
    downloader = MediaIoBaseDownload(buffer, request)
    done = False
    while not done:
        _status, done = downloader.next_chunk()
    return buffer.getvalue()


def _s3_key_for(file_meta, relative_path):
    mime_type = file_meta["mimeType"]
    if mime_type in GOOGLE_NATIVE_EXPORT_MIME_TYPES:
        _export_mime_type, ext = GOOGLE_NATIVE_EXPORT_MIME_TYPES[mime_type]
        if not relative_path.endswith(ext):
            relative_path += ext
    return relative_path


def handler(event, context):
    drive_service = _build_drive_service()
    folder_id = ssm.get_parameter(Name=GDRIVE_FOLDER_ID_SSM)["Parameter"]["Value"]

    files = _list_files_recursive(drive_service, folder_id)

    synced_keys = []
    failed_file_ids = []

    for file_meta, relative_path in files:
        s3_key = _s3_key_for(file_meta, relative_path)
        try:
            content = _download_file(drive_service, file_meta)
        except Exception:
            logger.exception(
                "Failed to download file id=%s name=%s", file_meta["id"], file_meta["name"]
            )
            failed_file_ids.append(file_meta["id"])
            continue

        s3.put_object(
            Bucket=KB_BUCKET_NAME,
            Key=s3_key,
            Body=content,
            Metadata={
                "gdrive-file-id": file_meta["id"],
                "gdrive-modified-time": file_meta.get("modifiedTime", ""),
            },
        )
        synced_keys.append(s3_key)

    logger.info(
        "gdrive_sync complete: synced=%d failed=%d", len(synced_keys), len(failed_file_ids)
    )

    return {
        "statusCode": 200,
        "body": json.dumps(
            {
                "synced_count": len(synced_keys),
                "failed_count": len(failed_file_ids),
                "synced_keys": synced_keys,
                "failed_file_ids": failed_file_ids,
            }
        ),
    }
