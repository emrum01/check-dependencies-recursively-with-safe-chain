# check-dependencies-recursively-with-safe-chain

セキュリティチェック付きで複数のリポジトリの依存関係を一括インストールするスクリプト

## 前提条件

このスクリプトを実行する前に、**Aikido Safe Chain**をインストールしてください。

### Safe Chainとは

`@aikidosec/safe-chain`は、npm、pnpm、yarn等のパッケージマネージャーコマンドを監視し、インストール前にパッケージのセキュリティをチェックするツールです。オープンソース脅威インテリジェンス「Aikido Intel」と連携し、マルウェアや悪意のあるパッケージを検出して警告します。

### インストール方法

```bash
# グローバルインストール
npm install -g @aikidosec/safe-chain

# インストール後、ターミナルを再起動してください
# （パッケージマネージャーのシェルエイリアスを有効化するため）
```

### 対応環境

- Node.js 18以上
- npm、pnpm、yarn、pnpx、npx対応
- CI/CD環境での利用には npm >= 10.4.0 を推奨（完全な依存関係ツリースキャンのため）

### セキュリティ機能

- **リアルタイムスキャン**: パッケージインストール時にマルウェアを自動検出
- **脅威インテリジェンス**: Aikido Intelデータベースと連携した最新の脅威情報
- **インストール阻止**: 危険なパッケージ検出時に自動的にインストールを停止

## 使用方法

```bash
# 基本的な使用方法
./check-all-repositories.sh ~/Github/SomeDirectory

# リポジトリ単位でスキャン（デフォルト）
./check-all-repositories.sh ~/Github/SomeDirectory

# 全体を再帰的にスキャン
./check-all-repositories.sh -r ~/Github/SomeDirectory

# 詳細表示付きで実行
./check-all-repositories.sh -v ~/Github/SomeDirectory

# ドライラン（実行せずに確認）
./check-all-repositories.sh -d ~/Github/SomeDirectory
```

## オプション

- `-r, --recursive`: ディレクトリ全体を再帰的に探索（リポジトリ単位ではなく）
- `-v, --verbose`: 詳細な出力を表示
- `-d, --dry-run`: 実際にはpnpm iを実行せず、package.jsonの場所のみ表示
- `-h, --help`: ヘルプを表示

## 機能

- 指定ディレクトリ内の全てのpackage.jsonを自動検出
- Safe Chainによるセキュリティチェック付きでpnpm installを実行
- 脆弱性・マルウェア検出時のアラート表示
- 実行結果の詳細レポート生成
- タイムアウト機能（60秒）

## 注意事項

- Safe Chainが未インストールの場合、通常のpnpm installが実行されセキュリティチェックは行われません
- CI/CD環境では適切な設定が必要です
- 初回実行時は依存関係のダウンロードに時間がかかる場合があります

