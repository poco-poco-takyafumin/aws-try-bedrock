# Google Drive API連携に必要な依存パッケージをLambda Layerとして用意する。
# terraform apply実行環境（開発者ローカル）でpip installし、そのままzip化する。
#
# レビュー指摘対応（2点）:
#   1. requirements.txtは「純Pythonのみ」を意図していたが、google-api-python-client経由で
#      protobuf等の非純Python（コンパイル済み）パッケージが実際には混入する。ビルド環境
#      （開発者のmac等）のアーキテクチャに依存しないよう、--platform/--only-binaryで
#      Lambda実行環境（Amazon Linux, x86_64, Python 3.12）向けのwheelを明示的に指定して
#      取得する。以前はこの指定がなく、ビルド環境ネイティブのwheelがそのまま混入し、
#      Lambda上でImportError（invalid ELF header等）になる不具合があった。
#   2. `.build/`はgitignore対象でリポジトリに含まれないため、フルcloneし直した環境や
#      state（このnull_resourceの実行記録）だけを引き継いだ環境では`.build/layer`が
#      存在しないことがある。triggersをrequirements.txtのハッシュだけに頼ると、
#      ハッシュが変化していない限りprovisionerが再実行されず、後続のarchive_fileが
#      source_dir不在で失敗する。そのためtriggersは常に変化する値にして毎回
#      provisionerを実行させ、実際にpip installするかどうかはシェル側で
#      ハッシュファイル＋ディレクトリ存在チェックにより判断する（冪等性の担保をTerraformの
#      trigger機構からシェルスクリプト側に移す）。
resource "null_resource" "install_dependencies" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      REQUIREMENTS_HASH="${filemd5("${path.module}/requirements.txt")}"
      HASH_FILE="${path.module}/.build/.gdrive_sync_layer_hash"
      LAYER_DIR="${path.module}/.build/layer"

      if [ -f "$HASH_FILE" ] && [ -d "$LAYER_DIR/python" ] && [ "$(cat "$HASH_FILE")" = "$REQUIREMENTS_HASH" ]; then
        exit 0
      fi

      rm -rf "$LAYER_DIR"
      mkdir -p "$LAYER_DIR/python"
      pip install -r ${path.module}/requirements.txt -t "$LAYER_DIR/python" \
        --platform manylinux2014_x86_64 \
        --implementation cp \
        --python-version 3.12 \
        --only-binary=:all: \
        --upgrade
      mkdir -p "${path.module}/.build"
      echo "$REQUIREMENTS_HASH" > "$HASH_FILE"
    EOT
  }
}

data "archive_file" "layer" {
  type        = "zip"
  source_dir  = "${path.module}/.build/layer"
  output_path = "${path.module}/.build/layer.zip"

  depends_on = [null_resource.install_dependencies]
}

resource "aws_lambda_layer_version" "deps" {
  layer_name          = "${var.name_prefix}-gdrive-sync-deps"
  filename            = data.archive_file.layer.output_path
  source_code_hash    = data.archive_file.layer.output_base64sha256
  compatible_runtimes = ["python3.12"]
}
