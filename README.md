# K8s-KANZEN-RIKAI
いろいろ試して理解していくためのリポジトリ。

## 実行環境
少なくともWindows 10のWSL2（Ubuntu）では動いたものを上げています。他では未確認。

## あそびかた
WSL2とDocker Desktop for Windowsのインストールはしているものとします。
```bash
source init.sh
```
でkindとkubectlのバイナリをゲット。ついでにPATHも通るので、```kind create cluster```ですぐに遊べる！
