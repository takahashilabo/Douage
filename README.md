# Douage - 胴上げ体験VR

Quest 3 のブラウザ（Meta Quest Browser / WebXR）で動く、優勝チームの胴上げをその中心で体験するVRアプリの最小実装（MVP）です。Godot 4.7 + WebXR で作られており、APKビルドやサイドロード不要で、URLを開くだけで体験できます。

## できること（現状のMVP）

- プレースホルダーの球場（芝生・内野・4方向の観客スタンド・照明塔）
- 周囲を囲む8人の選手（簡易モデル）が胴上げのタイミングで腕を振り上げる
- プレイヤーの頭（カメラ）が選手の胴上げに合わせて3回上下に揺れ、最後に高く掲げられて終わる
- 紙吹雪エフェクト
- WebXRで「VRに入る」ボタンからQuest 3のVRセッションを開始
- VR非対応ブラウザ（PCでの開発中など）では「プレビュー開始」で非VR確認も可能

## まだ無いもの（次のステップ）

- 歓声・応援SE（`CheerPlayer` ノードに `AudioStream` をセットすれば鳴るようにしてあります。音源ファイルをご用意ください）
- 本格的な3Dモデル（選手・球場はすべてプリミティブ形状のプレースホルダー）
- 移動・インタラクション（今回は「胴上げされる」体験に特化し、移動機能は意図的に省いています）

## プロジェクトを開く

Godot 4.7.x のエディタで `project.godot` を開いてください（本機にインストール済みの Godot.app は v4.7.2）。

## デスクトップでのプレビュー

エディタで `scenes/Main.tscn` を実行（F6）すると、WebXR非対応環境として認識され「プレビュー開始」ボタンが出ます。それを押すと胴上げシーケンスが再生されます（マウスで見回すことはできませんが、演出確認には十分です）。

## Quest 3 でテストする手順

### 1. Export Templates のインストール（重要）

現在インストールされている Export Template は **v4.6.3** ですが、エディタ本体は **v4.7.2** です。バージョンが一致していないとWeb書き出しができません。

Godotエディタで `Editor > Manage Export Templates...` を開き、v4.7.2 のテンプレートをダウンロード/インストールしてください（オフライン環境なら [godotengine.org/download/archive](https://godotengine.org/download/archive/) から `Godot_v4.7.2-stable_export_templates.tpz` を取得し、同ダイアログの「Install from File」で指定）。

### 2. Web書き出し設定を作る

1. `Project > Export...` を開く
2. `Add...` → `Web` を選択
3. `Export Path` を `build/web/index.html` などに設定
4. `Options` タブで `Variant > Thread Support` は **オフのままにする**（オンにするとCOOP/COEPヘッダーが必須になり、簡易サーバーでの配信が複雑になります。今回の体験はスレッド不要です）
5. `Export Project` で書き出す

### 3. ローカルHTTPSサーバーで配信する（mkcert方式）

WebXR はセキュアコンテキスト（HTTPS、または `localhost` 自身からのアクセス）が必須です。以前のARピアノアプリ (`piano02`) と同じ方式で、`mkcert` でLAN IP用の証明書を作り、同一LAN上のQuest 3からHTTPS経由でアクセスします（外部トンネル不要）。

初回のみ証明書を作成します（Macの LAN IP に置き換えてください。`ipconfig getifaddr en0` で確認できます）。

```bash
brew install mkcert   # 未インストールの場合
cd server
mkcert -key-file key.pem -cert-file cert.pem 192.168.x.x localhost 127.0.0.1
```

エクスポート後、プロジェクトルートでサーバーを起動します。

```bash
python3 server/serve.py
```

`https://<MacのLAN IP>:8070/` で配信されます。Quest 3 の Meta Quest Browser で同一アドレスを開いてください。`mkcert`のルートCAはQuest 3側には入っていないため、ブラウザで「この接続ではプライバシーが保護されません」のような警告が出ることがあります。その場合は「詳細設定」→「このまま続行」を選べば、HTTPS自体は有効なためWebXRは問題なく動作します。

### 4. Quest 3 で体験する

1. Meta Quest Browser で上記URLを開く
2. 画面中央の「VRに入る」ボタンをクリック（WebXRはユーザー操作がないとVRセッションを開始できない仕様のため、必ずボタン経由にしています）
3. ヘッドセットがVRモードに切り替わり、球場の中心に立った状態で胴上げが始まります

## コード構成

- `scenes/Main.tscn` - ルートシーン。XROrigin3D／UI／ライト等の最小構成のみを定義し、球場・選手・パーティクルは `main.gd` が実行時に生成します
- `scripts/main.gd` - WebXRセッション管理、胴上げのトス（Tweenで `Rig` ノードのY座標を上下）、選手の腕アニメーション、球場・観客・紙吹雪の生成ロジック

`Rig`（`Node3D`）が `XROrigin3D` の親になっており、胴上げのトス演出は **Rig自体を動かす**ことで実現しています。ユーザー自身の首振り・視線トラッキングは `XROrigin3D` 以下にそのまま反映されるため、VR酔いを抑えつつ「持ち上げられる」感覚を演出できます。

## カスタマイズのヒント

- `scripts/main.gd` の先頭にある定数（`TOSS_HEIGHT` / `TOSS_DURATION` / `TOSS_COUNT` / `TEAMMATE_COUNT` など）を変えるだけで、トスの高さ・回数・選手の数を調整できます
- 本格的な選手モデルや球場モデル（`.glb` など）を使う場合は `assets/` フォルダに配置し、`_build_teammates()` / `_build_stadium()` 内のプリミティブ生成部分を `load("res://assets/...")` に置き換えてください
