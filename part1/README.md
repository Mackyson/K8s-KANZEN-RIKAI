最近、一年も積んでいた「Kubernetes完全ガイド 第二版」をようやく読み始めました。  
そんなわけで、この本を読んでKubernetesを完全に理解したいと思い、とりあえず手を動かすことを決意しました。
以下、（バージョンによる違いがなければ）手順と結果の再現性はあると思いますが、解説的なアレはないです。知識がないからね。備忘録備忘録。

使用したOSするWindows 10です。
WinでローカルにKubernetesを立てるなら、minikubeかDocker Desktop for Windowsの付属のアレかkindか **自力** ですが、今回はkindを使うことにします。（minikubeは以前ハンズオンで触ったことがあるし、Dockerの付属のやつはできることしょぼいらしいので）

## インストール
### 今回インストールするもの
* Docker Desktop for Windows
* WSL2（Ubuntu）
* kubectl
* kind

### インストール手順

```bash
cd your_workspace

mkdir -p tmp/bin 

curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"

curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.12.0/kind-linux-amd64

mv ./kind ./kubectl tmp/bin

export PATH=$(pwd)+"/tmp/bin:$PATH"
```

DockerとWSL2は、ググってよしなにやってください（こんなの見てる時点でこの2つは既に入れてるだろうと思っている）  
また、[Docker Desktop for Windowsを入れたら勝手にWSL2でkubectlが入ってきます](https://kubernetes.io/ja/docs/tasks/tools/install-kubectl/#install-kubectl-on-windows)が、こいつは使いません。

```bash
$ kubectl version --client
$ kind version
```

を実行して

```bash
$ kubectl version --client
Client Version: version.Info{Major:"1", Minor:"23", GitVersion:"v1.23.6", GitCommit:"ad3338546da947756e8a88aa6822e9c11e7eac22", GitTreeState:"clean", BuildDate:"2022-04-14T08:49:13Z", GoVersion:"go1.17.9", Compiler:"gc", Platform:"linux/amd64"}

$ kind version
kind v0.12.0 go1.17.8 linux/amd64
```
ちゃんとバージョンが出てきたらとりあえずOKです（バージョンを気にする必要があるようなことは当面の間しないはず！）。

## Kubernetesクラスタの立ち上げ
```bash
$ kind create cluster
```
を実行して、しばらく待つと
```bash
Creating cluster "kind" ...
 ✓ Ensuring node image (kindest/node:v1.23.4) 
 ✓ Preparing nodes 
 ✓ Writing configuration 
 ✓ Starting control-plane 
 ✓ Installing CNI 
 ✓ Installing StorageClass 
Set kubectl context to "kind-kind"
You can now use your cluster with:

kubectl cluster-info --context kind-kind

Have a question, bug, or feature request? Let us know! https://kind.sigs.k8s.io/#community 
```
このとおり、立ち上がります。
特にDockerイメージを指定していなければ、デフォルトでkindest/nodeというイメージを使ったノード一つからなるクラスタが立ち上がります。  
僕は、とりあえずcurlで叩いてみる人間なので、
```bash
$ kubectl cluster-info
```
で、ポート（多分ランダム）を確認しまして、
```bash
Kubernetes control plane is running at https://127.0.0.1:44921
CoreDNS is running at https://127.0.0.1:44921/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```
アクセスをすると……！
```bash
$ curl localhost:44921
```

```bash
Client sent an HTTP request to an HTTPS server.
```
グエー

どうやら、現状このクラスタは外部からのアクセスを受け付けるものではないようで、httpsに直したリクエストを出しても認証できなくて死ぬ。おとなしくNginxでも立ち上げてくださいという感じなのかな？

とはいえ、動いていることは確認できたので、お片付け。
```bash
kind delete cluster
```

これにておしまい。