# OrbifolderBridge

[English](README.md)

> **⚠ 実験的パッケージ — メンテナンス保証なし**
>
> このパッケージは一時的なブリッジ実装であり、Julia General レジストリには**登録されていません**。
> C++製の `orbifolder`/`nonSUSYorbifolder` を OSCAR.jl から使えるようにするためだけに存在します。
> 予告なく破壊的変更が行われる場合があります。プロダクションコードでの使用は推奨しません。

ヘテロティック弦理論のオービフォールド・コンパクト化を構築・解析する2つのC++製ツールへの
Juliaブリッジパッケージです。

- [**orbifolder**](https://orbifolder.hepforge.org/)（Nilles, Ramos-Sánchez, Vaudrevange,
  Wingerter, [arXiv:1110.5229](https://arxiv.org/abs/1110.5229)） — SUSYヘテロティック・オービフォールダー
- [**nonSUSYorbifolder**](https://github.com/StringsIFUNAM/nonSUSYorbifolder)
  （Escalante-Notario, Pérez-Martínez, Ramos-Sánchez, Vaudrevange,
  [arXiv:2504.20137](https://arxiv.org/abs/2504.20137)） — その非SUSY版フォーク

両ツールともサブプロセスとして実行します（`mode = :susy` / `:nonsusy` で切替）。
`OrbifolderBridge.jl` はモデルファイルと `CPrompt` コマンド列を書き出し、対応するバイナリを
専用の一時ディレクトリで実行し、出力テキストをJuliaの構造体にパースします。さらにゲージ群や
物質場の表現については、実際の `Oscar.RootSystem`/`Oscar.WeightLatticeElem` オブジェクトへの
マッピングも可能です。

**`orbifolder`/`nonSUSYorbifolder` は各自でビルドする必要があります** — 本パッケージはこれらを
同梱・自動ビルドしません。詳細は下記[インストール](#インストール)を参照してください。

## インストール

パッケージを追加します（未登録のため開発モードで）:

```julia
using Pkg
Pkg.develop(url="https://github.com/xiupos/OrbifolderBridge.jl")
```

### 上流ツールのビルド

必要なバックエンドをソースからビルドし、生成されたバイナリを検出可能な場所に置いてください
（`PATH` に通す、または後述の環境変数 / `Preferences.jl` 設定で指定）。ビルド依存関係
（GSL, Boost, GNU Readline、`nonSUSYorbifolder` の場合はさらにAutotools）やトラブルシューティングは
[`docs/upstream_notes.md`](docs/upstream_notes.md) を参照してください。

```bash
# nonSUSYorbifolder
git clone https://github.com/StringsIFUNAM/nonSUSYorbifolder.git
cd nonSUSYorbifolder
autoreconf -fi   # リポジトリはautotools生成物を同梱していないため必要
./configure && make
# -> ./nonSUSYorbifolder

# orbifolder (SUSY版)
curl -O https://orbifolder.hepforge.org/source/V1.2.1/orbifolder-1.2.1.tgz
tar xzf orbifolder-1.2.1.tgz && cd orbifolder-1.2.1
./configure && make
# -> ./src/orbifolder/orbifolder
```

ビルドしたバイナリは、上流と同じ名前（`orbifolder`, `nonSUSYorbifolder`）で `PATH` に置くか、
明示的に指定します:

```julia
using OrbifolderBridge

# そのセッション限り:
ENV["ORBIFOLDER_BIN"] = "/path/to/orbifolder"
ENV["NONSUSYORBIFOLDER_BIN"] = "/path/to/nonSUSYorbifolder"

# または Preferences.jl でセッションをまたいで永続化:
set_orbifolder_binary!(:susy, "/path/to/orbifolder")
set_orbifolder_binary!(:nonsusy, "/path/to/nonSUSYorbifolder")
```

各バックエンドは `Geometry/` ディレクトリ（同梱の空間群定義ファイル一式。ビルドしたソースツリーの
ルートにあります）も必要とします。デフォルトではバイナリの隣から自動検出されますが、うまく
見つからない場合は `ORBIFOLDER_GEOMETRY_DIR`/`NONSUSYORBIFOLDER_GEOMETRY_DIR` または
`set_orbifolder_geometry_dir!` で上書きできます。

## クイックスタート

```julia
using OrbifolderBridge

# E8xE8格子上のZ3オービフォールド（点群 "Z3_1_1"。両バックエンドのソースツリーに
# Geometry/Geometry_Z3_1_1.txt として同梱されている）。
model = OrbifolderModel(;
    mode = :nonsusy,
    label = "Z3_1_1",
    point_group = "Z3_1_1",
    shift = (
        [0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0],
        [1//3, 1//3, -2//3, zeros(Int, 13)...],
    ),
)

spectrum = compute_spectrum(model)
println(spectrum.gauge_group)                 # GaugeGroup("TestConfig1", ["SO(10)","SU(3)","SO(16)"], 1)
println(length(spectrum.fields))               # 13

for f in spectrum.fields
    println(f.multiplicity, " × ", f.rep, "_", f.statistic, "  charges: ", f.charges)
end
```

### OSCARのルート系・表現へのマッピング

```julia
using Oscar, OrbifolderBridge

root_systems = gauge_group_root_systems(spectrum.gauge_group)  # Vector{RootSystem}、各因子ごと

for f in spectrum.fields
    weights = field_weights(root_systems, f)   # Vector{WeightLatticeElem}
    println(f.multiplicity, " × ", weights)
end
```

### 複数モデルの並列計算

```julia
models = [OrbifolderModel(; mode = :nonsusy, label = "M$i", point_group = "Z3_1_1", shift = shift_i)
          for (i, shift_i) in enumerate(candidate_shifts)]

spectra = compute_spectra(models; ntasks = 8)  # サブプロセス起動はasyncmapで並列化、パースは逐次
```

## API

### モデル構築

- `OrbifolderModel(; mode, label, point_group, shift, lattice = :E8xE8, wilson_lines = [])` —
  モデルを構築する。`shift` は単一の16次元ベクトル \\(V_1\\)、または対 \\((V_1, V_2)\\)。
  全フィールドの詳細はdocstringを参照。
- `model_file_text(model)` — 上流の `begin model ... end model` 形式のファイルテキストを生成する。

### モデルデータの計算

単一モデル・逐次実行:

- `compute_spectrum(model)` → `Spectrum`
- `compute_gauge_group(model)` → `GaugeGroup`
- `compute_twist(model)` → `Twist`
- `compute_shift_vectors(model)` → `Vector{ShiftVector}`
- `compute_wilson_lines(model)` → `WilsonLines`

複数モデル・並列実行（`ntasks` キーワードで並列度を制御。[アーキテクチャ](#アーキテクチャ)参照）:

- `compute_spectra`, `compute_gauge_groups`, `compute_twists`,
  `compute_shift_vectors_batch`, `compute_wilson_lines_batch`

### OSCARマッピング

- `algebra_to_cartan_type(algebra)` → `(family::Symbol, rank::Int)`、例: `"SU(3)" -> (:A, 2)`
- `gauge_group_root_systems(gauge_group)` → `Vector{RootSystem}`
- `representation_weight(root_system, rep)` / `field_weights(root_systems, field)` —
  印字された表現の次元に一致する最高ウェイトを、`find_weight_of_dimension` と
  （次元が負＝共役表現の場合は）`dual_weight` を用いて求める

### 低レベルの構成要素

- `run_orbifolder_script(mode, commands; files, timeout)` — 生のコマンド列をどちらかの
  バックエンドに対して実行し、テキストの実行記録を取得する
- `split_transcript(text)` / `output_for(pairs, command)` — 実行記録を
  `command => output` のペア列に分割する
- `parse_gauge_group`, `parse_spectrum`, `parse_twist`, `parse_shift_vectors`,
  `parse_wilson_lines` — 特定コマンドの出力テキストを直接パースする

## 既知の制約

- デフォルトのvev配置（`"TestConfig1"`）のみサポートしています。vev配置の切り替えは未実装です。
- 許容超ポテンシャル結合（`cd couplings`）はまだパースしていません。コマンド体系は調査済みですが、
  仕様を完全には解明できていません。詳細は `docs/upstream_notes.md` を参照してください。
- `find_weight_of_dimension` は、印字された表現の*次元*から、小さなDynkinラベルの組み合わせを
  探索してウェイトを決定します。これらのモデルの出力に実際に現れる表現（基本表現・随伴表現・
  ベクトル表現・スピノル表現など）は全てカバーしますが、Weyl次元公式の完全に一般的な逆写像では
  ありません。

## アーキテクチャ

各サブプロセス呼び出しは専用の `mktempdir()` で実行されるため、並列呼び出し（`compute_spectra` 等）
でファイルが競合することはありません。並列化されるのは「バイナリを起動し、完了を待ち、テキストを
取得する」処理のみで、`asyncmap` を使います。パース処理、特にOSCAR/GAPオブジェクトの構築は、
GAPがスレッドセーフでないため、その後逐次的に行います。

両バックエンドのコマンド体系・出力形式をどのように調査したか、また上流の新バージョンが出た際の
追従手順については [`docs/upstream_notes.md`](docs/upstream_notes.md) を参照してください。

## 動作要件

- Julia ≥ 1.10
- Oscar.jl ≥ 1
- `orbifolder` および/または `nonSUSYorbifolder`（各自ソースからビルド。上記参照）

## ライセンス

本ブリッジパッケージ自体は [MIT](LICENSE) ライセンスです。別途ビルド・実行する上流の
`orbifolder`/`nonSUSYorbifolder` は GPL ライセンスです — 各リポジトリを参照してください。
