# Google Workspace側セットアップ手順

Terraformでは自動化できない、Google Cloud / Google Workspace管理コンソール側の作業手順。
`modules/gdrive_sync` のLambdaがGoogle Driveへアクセスできるようにするための準備。

対象読者: このAWSアカウントの管理者、かつGoogle Workspaceの管理者権限を持つ人。

## 1. Google Cloud Projectの準備とDrive APIの有効化

1. [Google Cloud Console](https://console.cloud.google.com/) で新規プロジェクトを作成する（既存プロジェクトを流用しても良い）
2. 「APIとサービス」→「ライブラリ」から **Google Drive API** を有効化する

## 2. サービスアカウントの作成とJSONキーの発行

1. 「IAMと管理」→「サービスアカウント」→「サービスアカウントを作成」
   - 名前例: `bedrock-rag-gdrive-sync`
2. 作成したサービスアカウントの詳細画面 →「キー」タブ →「鍵を追加」→「新しい鍵を作成」→ **JSON形式**を選択してダウンロード
   - このJSONファイルは機密情報。ローカルに長期間置かない。手順5でAWS Secrets Managerに登録したら削除する
3. サービスアカウントの詳細画面に表示される**クライアントID**（数字の羅列）を控えておく（手順3で使用）

## 3. Google Workspace管理コンソールでのドメイン全体委譲設定

1. [Google Workspace管理コンソール](https://admin.google.com/) にドメイン管理者としてログイン
2. 「セキュリティ」→「アクセスとデータ管理」→「APIの制御」→「ドメイン全体の委任」を開く
3. 「新しく追加」をクリックし、以下を入力する
   - **クライアントID**: 手順2-3で控えたサービスアカウントのクライアントID
   - **OAuthスコープ**: `https://www.googleapis.com/auth/drive.readonly`
     （requirements.md確定: 読み取り専用に限定。書き込みスコープは付与しない）
4. 保存する

## 4. 同期対象フォルダの準備とフォルダIDの確認

1. Google Driveで同期対象の共有ドライブ/フォルダ（銀行・保険・取扱説明書・経費等の文書を格納）を用意する
2. 対象フォルダをブラウザで開き、URLの末尾（`https://drive.google.com/drive/folders/<ここがフォルダID>`）からフォルダIDを取得する
3. サービスアカウントはドメイン全体委譲により対象ドメイン内のファイルにアクセスできるため、
   個別にサービスアカウントをフォルダの共有先に追加する必要は基本的にない
   （委譲するユーザー＝フォルダ所有者のメールアドレスを手順6でSSM Parameter Storeに登録する）

## 5. AWS側へのシークレット登録（Terraform apply後）

`terraform apply` 後、`modules/gdrive_sync` が作成する以下のリソースに値を登録する:

```bash
# サービスアカウントJSONキーをSecrets Managerに登録
aws secretsmanager put-secret-value \
  --secret-id "$(terraform output -raw gdrive_sync_secret_arn)" \
  --secret-string file://path/to/downloaded-service-account-key.json

# 登録後、ローカルのJSONキーファイルは削除する
rm path/to/downloaded-service-account-key.json
```

## 6. フォルダID・委譲先ユーザーのSSM Parameter Store登録・変更

初期値はそれぞれTerraform変数 `gdrive_sync_folder_id_parameter_default` /
`gdrive_sync_impersonate_user_parameter_default` で設定されるが、運用中の変更はTerraformを
介さず以下で行う（コード変更・再デプロイ不要にするための設計）:

```bash
aws ssm put-parameter \
  --name "/<name_prefix>/gdrive-sync/folder-id" \
  --value "<新しいフォルダID>" \
  --type String \
  --overwrite

# ドメイン全体委譲でなりすます対象ユーザー（通常は手順4のフォルダ所有者）のメールアドレス
aws ssm put-parameter \
  --name "/<name_prefix>/gdrive-sync/impersonate-user" \
  --value "<フォルダ所有者のメールアドレス>" \
  --type String \
  --overwrite
```

## セキュリティ上の注意

- サービスアカウントのJSONキーはこのリポジトリにコミットしない（`.gitignore`で除外すること）
- ドメイン全体委譲は強力な権限のため、スコープは必要最小限（`drive.readonly`）に留める
- JSONキーをAWS Secrets Managerに登録した後は、ローカル・ダウンロードフォルダから確実に削除する
