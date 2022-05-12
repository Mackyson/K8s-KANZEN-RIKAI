## 前回のあらすじ
ついにnginxを起動してブラウザからアクセスすることに成功しました。

nginxを走らせるPodを立ち上げ、そのPodの80番ポートをServiceのNodePortを使ってホストマシンの特定のポートに公開することで動いています。

## マニフェストはこんな書き方もできるよ
前回の```service.yaml```と```nginx.yaml```を例にとると
```yaml
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: hello-service
spec:
  type: NodePort
  selector:
    app: nginx
  ports:
    - port: 80
      nodePort: 30001
      protocol: TCP
---
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  containers:
    - name: nginx
      image: nginx:latest
```
このように、```---```で区切れば一つのファイルで複数のリソースを記述できます。
これを```apply```すると
```bash
$ kubectl apply -f=service.yaml
service/hello-service created
pod/nginx created
```
こんな感じになって、二つ作れていることがわかります。今後は積極的にこういう書き方をしていきます。
## ReplicaSetとDeployment
前回、「ReplicaSetはPodを冗長化して管理するもの、DeploymentはReplicaSetを管理するもの」といいました。もうちょっとマシな説明をしていきます。
### ReplicaSet
名前から明らかですが、ReplicaSetの本質はレプリケーションです。  
ReplicaSetは指定したPodのレプリカを指定した数だけ作ってくれるリソースです。ただ作るだけでなく、作った後はレプリカ数を一定に保つように監視していて、Podが死んだら回復させてくれます（オートヒーリング）。ちなみに、Nodeが死んだ場合にも、別のNode上でPodを走らせることで、トータルのレプリカ数を維持します。 
ReplicaSetのおかげで、指定したレプリカ数だけPodが動いていることが保証されるわけですね。

昔はReplicationControllerという名前だったらしいです。[公式ドキュメント](https://kubernetes.io/docs/concepts/workloads/controllers/replicationcontroller/)を見るとdeprecatedの匂いが充満していますね。Kubernetesに歴史あり。

### Deployment
DeploymentはReplicaSetを管理しますが、ReplicasetとPodの関係とはまた違います。  
マサカリを恐れずに言うと、DeploymentはReplicaSetのアップデートを管理する機能です。もっというと、"ローリング"アップデートを上手いことやってくれます。  
通常のアップデート（Red/Black Deployを想定）はアップデートしたいReplicaSetのバージョンを一気に全部切り替えるのに対し、ローリングアップデートでは、古いバージョンのReplicaSet（旧RS）から新しいバージョンのReplicaSet（新RS）へ、少しずつ移行していきます（アップデート完了時に旧RSのレプリカ数は0になります）。  

例えば、（Deploymentを使わずに）ReplicaSetを作ったとしましょう。少し時間が経ち、アプリケーションの新しいバージョンができたので、ReplicaSetをアップデートすることになりました。ここで、新RSを作ってServiceの実行を新RSに全振りすると問題が発生したときにまずいことになります。すなわち、不幸にも本番環境でエラーが起きた場合には、サービスが完全にダウンすることになります。  
一方、リクエストを少しずつ新RSに流していくようにした場合はどうでしょう。こちらでは、新RSでサービスが崩壊したとしても旧RSは生きているので、アップデートの影響でサービス全体が完全に停止することはありません。"アップデートのためのメンテナンス"というダウンタイムも消えます。  
また、新RSが使い物にならないことがわかるとアップデートは即刻中止されますが、この時にすることは"ロールバック"ですよね。実はこちらもDeploymentの仕事のうちであり、Kubernetesの機能を使って旧RS時代へ戻すことができます。

### PodとReplicaSetとDeployment、どれを使えばいいのか
先ほどまでの説明から、DeploymentはReplicaSetを管理していて、ReplicaSetはPodを管理しているといえます。よって、我々は**常に最上位のオブジェクトであるDeploymentを使えばOK**です。<s>例外はきっとあるけど！</s>  
前回も言いましたが、公式ドキュメントでも[大抵の場合Deploymentを使うことが推奨されています](https://kubernetes.io/ja/docs/concepts/workloads/controllers/replicaset/#replicaset%E3%82%92%E4%BD%BF%E3%81%86%E3%81%A8%E3%81%8D)。

## Cluster, Deployment, Serviceの立ち上げ
Clusterのマニフェストはこちら。
```yaml
# cluster.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: hpa
nodes: 
  - role: control-plane
  - role: worker
    extraPortMappings:
    - containerPort: 30001
      hostPort: 8000
```
前回と名前が違うだけですが一応載せておきました。

続いて、Deployment, Serviceのマニフェストがこちら。
```yaml
# deploy.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hpa-deploy
  labels:
    app: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        resources:
          limits:
            cpu: 500m
          requests:
            cpu: 200m
---
apiVersion: v1
kind: Service
metadata:
  name: hpa-svc
spec:
  type: NodePort
  selector:
    app: nginx
  ports:
    - port: 80
      nodePort: 30001
```
長い記述ですが分解していけば何をやっているかは簡単です（難しいとぼくもわからない）。

とりあえずNodePortについては名前以外前回と同じであることがわかると思います。

Deploymentについてですが、```templete: ```以下を見ると、一旦```resources:```という新キャラを見なかったことにすると、前回のPodのマニフェストで全く同じ記述がありましたね。```templete```はレプリケーションしたいPodのspecificationを書いている場所になります。

```resources:```ですが、ここにはPodが要求する計算資源の量が書いてあります。CPUの場合、1000mを指定すればCPU1コア分の計算資源が割り当てられます。ちなみに、1m単位で指定できます。今回は要求量が200mで上限が500mということになります。メモリも指定できますが割愛！

次に、ネストが浅い方の```spec: ```以下に注目すると、```replicas: 1```や```templete: ```を従えていることから、これはReplicaSetのspecificationであることがなんとなくわかります。Deploymentのspecificationを記述している```spec: ```がないのは、Deploymentはアップデート時の挙動以外はReplicaSetと等価なので、ReplicaSetのspecがあれば十分だからですね（実は等価じゃないかもしれんけどちょっと触った程度の僕には、アップデート以外の部分でのReplicaSetとDeploymentの違いはわかりませんでした。ごめんね！）。

以上から、このDeploymentはnginxを積んだコンテナ1個（レプリカ数が1だから）を起動して、そいつの80番ポートとホストマシンの8000番ポートを繋げることを意味していることがわかります。

```bash
$ kind create cluster --config=cluster.yaml
$ kubectl apply -f deploy.yaml
```
で早速起動しましょう。

## Horizontal Pod Autoscaler（HPA）でオートスケーリングをしてみよう
### HPAとは
HPAはDeployment、ReplicaSet、StatefulSet（まだ未登場）といった、k8sがレプリケーションしてくれるやつのレプリカ数を、CPU使用率などのメトリクスを使って自動で増減してくれるリソースです。水平にスケールするからHorizontal。

Horizontalがあるなら当然Vertical Pod Autoscalerもある（自動でPodに割り当てる計算資源を変えてくれる）のですがこちらはあんまり使われていないような気がします。

HPAが使うメトリクスですが、Kubernetesが自動でいい感じに監視してくれていると思いきや、そうでもないです。k8sではMetrics APIを通してコンテナのCPU使用率などを見られるのですが、[このAPIはプラグインによって実装される](https://thinkit.co.jp/article/18822#:~:text=Metrics%20API%E3%81%AF%E3%83%97%E3%83%A9%E3%82%B0%E3%82%A4%E3%83%B3%E3%81%AB%E3%82%88%E3%82%8A%E5%AE%9F%E8%A3%85%E3%81%95%E3%82%8C%E3%82%8B%E3%82%82%E3%81%AE)らしく、公式では[メトリクスサーバがないとMetrics APIは利用できない](https://kubernetes.io/ja/docs/tasks/debug-application-cluster/resource-metrics-pipeline/#:~:text=%E5%82%99%E8%80%83%3A%20%E3%83%A1%E3%83%88%E3%83%AA%E3%82%AF%E3%82%B9API%E3%82%92%E4%BD%BF%E7%94%A8%E3%81%99%E3%82%8B%E3%81%AB%E3%81%AF%E3%80%81%E3%82%AF%E3%83%A9%E3%82%B9%E3%82%BF%E3%83%BC%E5%86%85%E3%81%AB%E3%83%A1%E3%83%88%E3%83%AA%E3%82%AF%E3%82%B9%E3%82%B5%E3%83%BC%E3%83%90%E3%83%BC%E3%81%8C%E9%85%8D%E7%BD%AE%E3%81%95%E3%82%8C%E3%81%A6%E3%81%84%E3%82%8B%E5%BF%85%E8%A6%81%E3%81%8C%E3%81%82%E3%82%8A%E3%81%BE%E3%81%99%E3%80%82%E3%81%9D%E3%81%86%E3%81%A7%E3%81%AA%E3%81%84%E5%A0%B4%E5%90%88%E3%81%AF%E5%88%A9%E7%94%A8%E3%81%A7%E3%81%8D%E3%81%BE%E3%81%9B%E3%82%93%E3%80%82)と明記されています。

というわけでクラスタにメトリクスサーバを立てましょう。

### Metrics Serverを立てよう
Metrics Serverは、コンテナを監視しているkubeletのSummary APIから統計情報を得て、それをkube-api-serverからアクセスできるようにしてくれる人です。この人をクラスタに召喚すればMetrics APIが使えるようになり、```kubectl top nodes```とかの```top```系が動くようになります。

ちなみに、Metrics Serverはメトリクスの精度が重要な場合には適していなくて、あくまでHPA（とVPA）のために使うものだそうです。

さて、リポジトリのREADMEの[Installation](https://github.com/kubernetes-sigs/metrics-server#installation)に従い、以下のコマンドを実行しましょう。
```bash
$ kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

serviceaccount/metrics-server created
clusterrole.rbac.authorization.k8s.io/system:aggregated-metrics-reader created
clusterrole.rbac.authorization.k8s.io/system:metrics-server created
rolebinding.rbac.authorization.k8s.io/metrics-server-auth-reader created
clusterrolebinding.rbac.authorization.k8s.io/metrics-server:system:auth-delegator created
clusterrolebinding.rbac.authorization.k8s.io/system:metrics-server created
service/metrics-server created
deployment.apps/metrics-server created
apiservice.apiregistration.k8s.io/v1beta1.metrics.k8s.io created
```
これで、クラスタにMetrics Serverをインストールできました

……と思いきや、```kubectl top nodes```はまだ動きません。
```bash
$ kubectl top nodes

Error from server (ServiceUnavailable): the server is currently unable to handle the request (get nodes.metrics.k8s.io)
```
Metrics ServerのPodを確認してみると、
```bash
$ kubectl get po -A
NAMESPACE            NAME                                        READY   STATUS    RESTARTS   AGE
...
kube-system          metrics-server-847dcc659d-mrldn             0/1     Running   0          96s
...
```
Metrics ServerのPodが一向にReadyにならないことがわかります。

調べてみたところ、
[kindのIssueのコメント](https://github.com/kubernetes-sigs/kind/issues/398#issuecomment-478311167)に解決策がありました。
```bash
kubectl edit deploy metrics-server -n kube-system
```
で、```args```の部分に、``` - --kubelet-insecure-tls```を追加すると、
```bash
kubectl get po -A
NAMESPACE            NAME                                        READY   STATUS    RESTARTS   AGE
...
kube-system          metrics-server-5c85b4d56f-8m5bk             1/1     Running   0          56s
...
```
無事Readyになりました。```top```を動かしてみると
```bash
kubectl top nodes
NAME                CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
hpa-control-plane   629m         7%     710Mi           2%
hpa-worker          130m         1%     225Mi           0%
```
OK！

ちなみに、minikubeならアドオン入れるだけでOKという簡単仕様らしいので、Metrics Serverが必要ならminikubeでやってもいいかも。

### HPAリソースの立ち上げ
HPAリソースもマニフェストを書いて立ち上げることはできるのですが、公式のQuick Start的なやつにコマンドで立ち上げるやつが載っているので、今回はそれを使います。というわけで以下を実行。
```bash
$ kubectl autoscale deployment hpa-deploy --cpu-percent=50 --min=1 --max=10

horizontalpodautoscaler.autoscaling/hpa-deploy autoscaled
```
さて、ちゃんと作ったdeploymentがhpaできるようになっているかを確認しましょう。
```bash
$ kubectl get hpa
NAME         REFERENCE               TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
hpa-deploy   Deployment/hpa-deploy   <unknown>/50%   1         10        1          26s
```
作ってすぐはメトリクスの情報が届いてないので、unknownになります。
しばらくすると、
```bash
$ kubectl get hpa
NAME         REFERENCE               TARGETS    MINPODS   MAXPODS   REPLICAS   AGE
hpa-deploy   Deployment/hpa-deploy   0%/50%    1         10        1          18m
```
こんな感じで、リソースの使用率が見えます。AGEの値が無駄にデカいですが、別に18分待たないといけないわけではなく、デフォルトでは30秒間隔でメトリクスを取得するらしいです。だからといって30秒待てば動くわけではないですが。

### ServiceにDoSアタックを仕掛けよう
HPAが立ち上がったので、DoSアタックでCPU使用率を爆上げさせれば、レプリカ数が増えることが期待されます！というわけで```ab```コマンドでDoSアタックを仕掛けましょう！
デフォルトでは入ってないので、お持ちでない方は次のコマンドをどうぞ。
```bash
$ sudo apt install apache2-utils
```
それでは、次のコマンドでDoSアタックが始まります。nやcはPCのスペックに合わせて適当に弄ってください．
```bash
$ ab -n 100000 -c 10 http://localhost:8000/
```
30秒ほど待ってHPAリソースの様子を見てみると
```bash
$ kubectl get hpa
NAME         REFERENCE               TARGETS    MINPODS   MAXPODS   REPLICAS   AGE
hpa-deploy   Deployment/hpa-deploy   207%/50%   1         10        1          48m
```
CPU使用率が爆上がりしています。
続けて、もうちょっとだけ待ってから再び見てみると
```bash
$ kubectl get hpa
NAME         REFERENCE               TARGETS    MINPODS   MAXPODS   REPLICAS   AGE
hpa-deploy   Deployment/hpa-deploy   207%/50%   1         10        4          48m
```
レプリカ数が増えてますね！オートスケールができていることがわかります。ちなみに、最終的にレプリカ数は6まで増えました。

さて、レプリカ数が減らないうちに、もう一度同じ条件で```ab```コマンドを実行して、処理速度の違いを確認してみましょう。

1回目（最初はレプリカ数1）の結果は以下
```
$ ab -n 100000 -c 10 http://localhost:8000/
...
Time taken for tests:   61.301 seconds
...
Requests per second:    1631.30 [#/sec] (mean)
...
```
2回目（最初からレプリカ数6）の結果は以下
```
$ ab -n 100000 -c 10 http://localhost:8000/
...
Time taken for tests:   46.180 seconds
...
Requests per second:    2165.45 [#/sec] (mean)
...
```
トータルでかかった時間が15秒減り、1秒当たりに捌くリクエストが500件ほど増えていますね！HPAの力は偉大💪

## お気持ち
ReplicaSetの[ユースケース](https://kubernetes.io/ja/docs/concepts/workloads/controllers/replicaset/#replicaset%E3%82%92%E4%BD%BF%E3%81%86%E3%81%A8%E3%81%8D)に、アップデートされないReplicaSetはDeploymentによる管理が不要みたいに書いてたけど、別にDeploymentで管理してもいいと思う。  
となると、ReplicaSetはユーザ独自の戦略でアップデートしたいときのみ、直接使われるということになるはず。しかし、外部のプラグインを使うと[カナリーリリースとかもできるらしい](https://hi1280.hatenablog.com/entry/2019/10/12/115144)ので、結局ReplicaSetが直接使われることはないんじゃないか。

## お片付け
```bash
$ kind delete cluster --name=hpa
```
## 次回予告
* Persistent VolumeとかStatefulSetをやる
* fluentdとか立ち上げてDaemonSetも一緒にやるかも？

これにておしまい。