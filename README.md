# UWBViewerSystem

## プロジェクト構造

```
.
├── Devices 　　　　　　　　　　　　# デバイスにまつわるAPIをまとめておきます
├── Domain
│   ├── Adapter　　　　　　　　　　　 # 外部サービスへの接続を行います
│   ├── Repository                # アプリ内部に関係するデバイスAPIに接続を行います（主にDB）
│   └── Usecase                   # ビジネスロジックを書きます
└── Presentation
    ├── Components                # 全ての画面で使用をするコンポーネントを記述します
    ├── Router                    # 画面遷移にまつわるロジックがまとまっています
    └── Scenes　　　　　　　　　　　　# 各画面にまつわるUIがまとまっています。ViewModelもここに記載します
```