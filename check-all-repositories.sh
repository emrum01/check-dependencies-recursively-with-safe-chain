#!/bin/bash

# 色の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# デフォルト値
MODE="repo"  # "repo" or "recursive"
VERBOSE=0
DRY_RUN=0

# 使用方法を表示
show_usage() {
    echo "使用方法: $0 [オプション] <ディレクトリパス>"
    echo ""
    echo "オプション:"
    echo "  -r, --recursive    ディレクトリ全体を再帰的に探索（リポジトリ単位ではなく）"
    echo "  -v, --verbose      詳細な出力を表示"
    echo "  -d, --dry-run      実際にはpnpm iを実行せず、package.jsonの場所のみ表示"
    echo "  -h, --help         このヘルプを表示"
    echo ""
    echo "例:"
    echo "  $0 ~/Github/Business                    # リポジトリ単位でスキャン"
    echo "  $0 -r ~/Github/Business                 # 全体を再帰的にスキャン"
    echo "  $0 -r -v ~/Github/Business              # 詳細表示付きで再帰スキャン"
    echo "  $0 -d ~/Github/Business                 # ドライラン（実行せずに確認）"
    exit 0
}

# オプション解析
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--recursive)
            MODE="recursive"
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        -*)
            echo "不明なオプション: $1"
            show_usage
            ;;
        *)
            TARGET_DIR="$1"
            shift
            ;;
    esac
done

# 引数チェック
if [ -z "$TARGET_DIR" ]; then
    echo -e "${RED}エラー: ディレクトリパスを指定してください${NC}"
    show_usage
fi

# ディレクトリの存在確認
if [ ! -d "$TARGET_DIR" ]; then
    echo -e "${RED}エラー: ディレクトリ '$TARGET_DIR' が存在しません${NC}"
    exit 1
fi

# 絶対パスに変換
TARGET_DIR=$(cd "$TARGET_DIR" && pwd)

# 結果を格納する配列
declare -a ALL_PACKAGE_LOCATIONS=()
declare -a SUCCESS_INSTALLS=()
declare -a SAFE_CHAIN_ERROR_INSTALLS=()
declare -a GENERAL_ERROR_INSTALLS=()
declare -a SKIPPED_LOCATIONS=()

# エラー詳細を格納する連想配列
declare -A ERROR_DETAILS=()

# プログレスバー表示関数
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local progress=$((current * width / total))
    
    printf "\r["
    printf "%${progress}s" | tr ' ' '='
    printf "%$((width - progress))s" | tr ' ' ' '
    printf "] %d/%d" "$current" "$total"
}

# ヘッダー表示
echo "==================================="
echo -e "${WHITE}safe-chain セキュリティチェッカー v2.0${NC}"
echo "==================================="
echo "対象ディレクトリ: $TARGET_DIR"
echo "モード: $([ "$MODE" = "recursive" ] && echo "完全再帰探索" || echo "リポジトリ単位")"
echo "ドライラン: $([ $DRY_RUN -eq 1 ] && echo "有効" || echo "無効")"
echo "詳細表示: $([ $VERBOSE -eq 1 ] && echo "有効" || echo "無効")"
echo "==================================="
echo ""

# package.jsonを探索する関数
find_package_json() {
    local search_dir="$1"
    local prefix="$2"
    
    if [ $VERBOSE -eq 1 ]; then
        echo -e "${CYAN}[探索開始] $search_dir${NC}"
    fi
    
    # findコマンドで完全な再帰探索
    # -prune を使って除外ディレクトリを効率的にスキップ
    local find_cmd="find \"$search_dir\" \
        \\( -type d \\( \
            -name 'node_modules' -o \
            -name '.git' -o \
            -name '.cache' -o \
            -name '.next' -o \
            -name 'dist' -o \
            -name 'build' -o \
            -name 'coverage' -o \
            -name '.turbo' -o \
            -name '.vercel' -o \
            -name '.nuxt' -o \
            -name 'out' \
        \\) -prune \\) -o \
        -type f -name 'package.json' -print 2>/dev/null"
    
    local package_files=$(eval "$find_cmd")
    
    if [ -n "$package_files" ]; then
        while IFS= read -r package_file; do
            if [ -z "$package_file" ]; then
                continue
            fi
            
            local package_dir=$(dirname "$package_file")
            local relative_path="${package_dir#$TARGET_DIR/}"
            
            # 深さを計算
            local depth=$(echo "$relative_path" | tr '/' '\n' | wc -l)
            
            ALL_PACKAGE_LOCATIONS+=("$package_dir|$prefix$relative_path|$depth")
            
            if [ $VERBOSE -eq 1 ]; then
                echo -e "  ${GREEN}✓${NC} 発見: $relative_path (深さ: $depth)"
            fi
        done <<< "$package_files"
    fi
}

# STEP 1: package.jsonを探索
echo -e "${BLUE}[STEP 1/3] package.json を探索中...${NC}"

if [ "$MODE" = "recursive" ]; then
    # 完全再帰モード：ディレクトリ全体を一度に探索
    find_package_json "$TARGET_DIR" ""
else
    # リポジトリモード：各.gitディレクトリを含むフォルダを個別に探索
    repo_count=0
    for repo_dir in "$TARGET_DIR"/*; do
        if [ ! -d "$repo_dir" ]; then
            continue
        fi
        
        if [ ! -d "$repo_dir/.git" ]; then
            if [ $VERBOSE -eq 1 ]; then
                echo -e "${YELLOW}[スキップ] $(basename "$repo_dir") (.gitなし)${NC}"
            fi
            continue
        fi
        
        repo_name=$(basename "$repo_dir")
        ((repo_count++))
        
        echo -e "${CYAN}[リポジトリ $repo_count] $repo_name${NC}"
        find_package_json "$repo_dir" "$repo_name/"
    done
fi

echo ""
echo -e "${GREEN}探索完了: ${#ALL_PACKAGE_LOCATIONS[@]} 個の package.json を発見${NC}"

# 深さ統計を表示
if [ ${#ALL_PACKAGE_LOCATIONS[@]} -gt 0 ]; then
    max_depth=0
    min_depth=999
    for location_info in "${ALL_PACKAGE_LOCATIONS[@]}"; do
        IFS='|' read -r package_dir relative_path depth <<< "$location_info"
        [ $depth -gt $max_depth ] && max_depth=$depth
        [ $depth -lt $min_depth ] && min_depth=$depth
    done
    echo -e "${CYAN}深さの範囲: $min_depth ～ $max_depth${NC}"
fi
echo ""

# package.jsonが見つからなかった場合
if [ ${#ALL_PACKAGE_LOCATIONS[@]} -eq 0 ]; then
    echo -e "${YELLOW}package.jsonが見つかりませんでした。${NC}"
    echo ""
    echo -e "${CYAN}トラブルシューティング:${NC}"
    echo "1. 対象ディレクトリに package.json が存在するか確認"
    echo "2. パーミッションの問題がないか確認"
    echo "3. -v オプションで詳細出力を有効にして再実行"
    exit 0
fi

# ドライランモード
if [ $DRY_RUN -eq 1 ]; then
    echo "==================================="
    echo -e "${YELLOW}[ドライラン] 発見された package.json の一覧${NC}"
    echo "==================================="
    
    # 深さでソート
    IFS=$'\n' sorted=($(for location_info in "${ALL_PACKAGE_LOCATIONS[@]}"; do
        echo "$location_info"
    done | sort -t'|' -k3 -n))
    
    current_depth=-1
    for location_info in "${sorted[@]}"; do
        IFS='|' read -r package_dir relative_path depth <<< "$location_info"
        
        if [ $depth -ne $current_depth ]; then
            current_depth=$depth
            echo ""
            echo -e "${BLUE}深さ $depth:${NC}"
        fi
        
        echo -e "  ${CYAN}→${NC} $relative_path"
    done
    
    echo ""
    echo "==================================="
    echo "統計:"
    echo "  総数: ${#ALL_PACKAGE_LOCATIONS[@]} 個"
    echo "  最大深さ: $max_depth"
    echo "  最小深さ: $min_depth"
    echo "==================================="
    echo ""
    echo -e "${YELLOW}ドライランモードのため、pnpm i は実行されませんでした。${NC}"
    exit 0
fi

# STEP 2: 依存関係のインストール
echo "==================================="
echo -e "${BLUE}[STEP 2/3] 依存関係インストール開始${NC}"
echo "==================================="
echo ""

# ソートして浅い階層から処理
IFS=$'\n' sorted=($(for location_info in "${ALL_PACKAGE_LOCATIONS[@]}"; do
    echo "$location_info"
done | sort -t'|' -k3 -n))

total=${#sorted[@]}
current=0

for location_info in "${sorted[@]}"; do
    IFS='|' read -r package_dir relative_path depth <<< "$location_info"
    
    ((current++))
    
    if [ $VERBOSE -eq 0 ]; then
        show_progress $current $total
    else
        echo -e "${YELLOW}[$current/$total] 処理中: $relative_path (深さ: $depth)${NC}"
    fi
    
    # ディレクトリに移動
    cd "$package_dir" 2>/dev/null || {
        echo -e "\n  ${RED}✗ ディレクトリアクセスエラー${NC}"
        GENERAL_ERROR_INSTALLS+=("$relative_path")
        continue
    }
    
    # pnpm iの実行
    output=$(timeout 60 pnpm i 2>&1)
    exit_code=$?
    
    # タイムアウトチェック
    if [ $exit_code -eq 124 ]; then
        if [ $VERBOSE -eq 1 ]; then
            echo -e "  ${YELLOW}⏱ タイムアウト (60秒)${NC}"
        fi
        SKIPPED_LOCATIONS+=("$relative_path")
    # safe-chainエラーチェック
    elif echo "$output" | grep -iE "(Exiting without installing|malicious packages|safe-chain.*(block|malware|threat|vulnerable|dangerous))" > /dev/null; then
        if [ $VERBOSE -eq 0 ]; then
            echo ""  # プログレスバーをクリア
        fi
        echo -e "  ${RED}⚠️  safe-chain セキュリティエラー検出！${NC}"
        SAFE_CHAIN_ERROR_INSTALLS+=("$relative_path")
        
        # エラー詳細を保存
        error_detail=$(echo "$output" | grep -iE "(safe-chain|Exiting|malicious|block|malware|threat|vulnerable)" -B 3 -A 3)
        ERROR_DETAILS["$relative_path"]="$error_detail"
        
        if [ $VERBOSE -eq 1 ]; then
            echo "$error_detail" | head -10 | sed 's/^/    /'
        fi
    # その他のエラー
    elif [ $exit_code -ne 0 ]; then
        if [ $VERBOSE -eq 1 ]; then
            echo -e "  ${RED}✗ インストールエラー (コード: $exit_code)${NC}"
            echo "$output" | tail -5 | sed 's/^/    /'
        fi
        GENERAL_ERROR_INSTALLS+=("$relative_path")
        ERROR_DETAILS["$relative_path"]=$(echo "$output" | tail -15)
    # 成功
    else
        if [ $VERBOSE -eq 1 ]; then
            echo -e "  ${GREEN}✓ 成功${NC}"
        fi
        SUCCESS_INSTALLS+=("$relative_path")
    fi
    
    cd - > /dev/null || exit
done

if [ $VERBOSE -eq 0 ]; then
    echo ""  # プログレスバーをクリア
fi
echo ""

# STEP 3: 結果サマリー
echo "==================================="
echo -e "${BLUE}[STEP 3/3] 実行結果サマリー${NC}"
echo "==================================="
echo ""

# 統計
echo -e "${WHITE}統計:${NC}"
echo "  探索した package.json: ${#ALL_PACKAGE_LOCATIONS[@]} 個"
echo -e "  ${GREEN}成功: ${#SUCCESS_INSTALLS[@]}${NC}"
echo -e "  ${RED}safe-chainエラー: ${#SAFE_CHAIN_ERROR_INSTALLS[@]}${NC}"
echo -e "  ${RED}一般エラー: ${#GENERAL_ERROR_INSTALLS[@]}${NC}"
echo -e "  ${YELLOW}スキップ: ${#SKIPPED_LOCATIONS[@]}${NC}"
echo ""

# safe-chainエラーの詳細
if [ ${#SAFE_CHAIN_ERROR_INSTALLS[@]} -gt 0 ]; then
    echo -e "${RED}════════════════════════════════════${NC}"
    echo -e "${RED}⚠️  セキュリティアラート ⚠️${NC}"
    echo -e "${RED}════════════════════════════════════${NC}"
    echo -e "${RED}safe-chain により以下の場所で${NC}"
    echo -e "${RED}脆弱性/マルウェアが検出されました:${NC}"
    echo ""
    
    for location in "${SAFE_CHAIN_ERROR_INSTALLS[@]}"; do
        echo -e "  ${RED}⚠️${NC}  $location"
        
        if [ $VERBOSE -eq 1 ] && [ -n "${ERROR_DETAILS[$location]}" ]; then
            echo "     詳細:"
            echo "${ERROR_DETAILS[$location]}" | sed 's/^/       /'
            echo ""
        fi
    done
    
    echo -e "${RED}════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}推奨アクション:${NC}"
    echo "1. 各プロジェクトで 'pnpm audit' を実行"
    echo "2. package-lock.json を確認"
    echo "3. 依存関係を最新バージョンに更新"
    echo ""
fi

# 成功リスト（詳細表示モードの場合）
if [ $VERBOSE -eq 1 ] && [ ${#SUCCESS_INSTALLS[@]} -gt 0 ]; then
    echo -e "${GREEN}成功したインストール:${NC}"
    for location in "${SUCCESS_INSTALLS[@]}"; do
        echo -e "  ${GREEN}✓${NC} $location"
    done
    echo ""
fi

# 終了コード
if [ ${#SAFE_CHAIN_ERROR_INSTALLS[@]} -gt 0 ]; then
    exit 2
elif [ ${#GENERAL_ERROR_INSTALLS[@]} -gt 0 ]; then
    exit 1
else
    echo -e "${GREEN}✓ すべての処理が正常に完了しました${NC}"
    exit 0
fi