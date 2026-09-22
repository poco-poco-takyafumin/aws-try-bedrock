"""Google Drive -> S3 同期Lambda（プレースホルダー）。

Phase Aではインフラの箱（Lambda, IAMロール, Secrets Manager, SSM Parameter Store）のみを
用意し、実際のGoogle Drive API連携ロジックはPhase Bで実装する。

Phase Bで実装する内容の概要（requirements.md / 実装計画より）:
  1. SSM Parameter Store からS3書き込み用フォルダ ID を取得する
  2. Secrets Manager からサービスアカウントJSONキーを取得する
  3. サービスアカウント (ドメイン全体委譲, スコープ drive.readonly) でGoogle Drive APIに認証する
  4. 対象フォルダ配下のファイル一覧を取得し、S3バケット (env: KB_BUCKET_NAME) に同期する
  5. 同期時にPIIマスキング・文書ごとのアクセス範囲タグ付けを行う（詳細は実装セッションで確定）
"""

import json


def handler(event, context):
    return {
        "statusCode": 501,
        "body": json.dumps(
            {
                "message": "gdrive_sync is not implemented yet (Phase B).",
            }
        ),
    }
