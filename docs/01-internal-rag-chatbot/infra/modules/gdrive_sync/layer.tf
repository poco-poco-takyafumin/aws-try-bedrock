# Google Drive API連携に必要な依存パッケージをLambda Layerとして用意する。
# terraform apply実行環境（開発者ローカル）でpip installし、そのままzip化する。
# requirements.txtは意図的に純Pythonパッケージのみで構成しており（google-auth-httplib2/README参照）、
# ビルド環境とLambda実行環境(Amazon Linux)のアーキテクチャが異なっても互換性の問題は生じない。
resource "null_resource" "install_dependencies" {
  triggers = {
    requirements_hash = filemd5("${path.module}/requirements.txt")
  }

  provisioner "local-exec" {
    command = <<-EOT
      rm -rf ${path.module}/.build/layer
      mkdir -p ${path.module}/.build/layer/python
      pip install -r ${path.module}/requirements.txt -t ${path.module}/.build/layer/python --no-compile
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
