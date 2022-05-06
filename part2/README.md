## 前回のあらすじ
```bash
$ kind create cluster
```
で無のクラスタができました。  
```bash
$ kubectl cluster-info
```
でcontrol planeのAPI server（後述）のポートを見つけて、無謀にもcurlでリクエストを出し、無事門前払いされました。

## クラスタ生成時に自動生成されるPodを眺めてみよう
```bash
$ kind create cluster
```
を行ったとき、バックヤードではKubernetesクラスタの司令塔であるところのコントロールプレーンが作成されています。コントロールプレーンがないとクラスタは動きません。  ちなみにクラウド環境だとコントロールプレーンはプロバイダが提供してくれるらしいです。  
コントロールプレーンには、クラスタを管理するための4つのPodが積まれています。次のコマンドで確認可能です。
```bash
$ kubectl get pods --all-namespaces | grep kind-control-plane
```
結果は以下
```
kube-system          etcd-kind-control-plane                      1/1     Running   0          9m57s
kube-system          kube-apiserver-kind-control-plane            1/1     Running   0          9m59s
kube-system          kube-controller-manager-kind-control-plane   1/1     Running   0          9m57s
kube-system          kube-scheduler-kind-control-plane            1/1     Running   0          9m57s
```
etcd、kube-apiserver、kube-controller-manager、kube-schedulerの4つですね、  
etcdはKey Value Storeであり、クラスタに関する情報が保存されています。  
kube-apiserverは、```kubectl apply```とかのクラスタをいじるためのKubernetesのAPIを外部に公開している人です。kubectlコマンドは全てここへと通じます。認証されてないユーザがクラスタをいじれるとまずいのでここにブラウザで殴り込みをかけると当然ながら、無慈悲な弾かれが発生します（1敗）。RBACという方式でアクセス制御しているらしいです。  
kube-controller-managerは、Nodeが死んだときの対応や、Podが死んだときのオートヒーリングの実行など、多くの役割があります。  
kube-schedulerは、Podを走らせるNodeを決める役割があります。決め方はリソース要求量とか、各種制約とか、いろいろな指標が考慮されるようです。  
といった話は全て[こちらの公式ドキュメント](https://kubernetes.io/ja/docs/concepts/overview/components/#%E3%82%B3%E3%83%B3%E3%83%88%E3%83%AD%E3%83%BC%E3%83%AB%E3%83%97%E3%83%AC%E3%83%BC%E3%83%B3%E3%82%B3%E3%83%B3%E3%83%9D%E3%83%BC%E3%83%8D%E3%83%B3%E3%83%88)に書いてありますので、一読してみてください。別にエキスパートでもなんでもない謎の人間のブログより公式ドキュメント、これ鉄則。

さて、この記事の存在価値を全否定したところで、今回はNginxを立ち上げてトップページを確認するところまで行きます。

## Nginxを立ち上げよう
### の前に
Pod、Service、Nodeに関して言及したいと思います。

PodはKubernetesで動かしたいプロセス（大抵はアプリケーション）を実際に実行してくれるやつです。つまり、こいつがすべての基本になります。
その中身は1つ以上のコンテナであり、メインのコンテナと、それを補佐するサブのコンテナ（EnvoyやIstioみたいなプロキシとか、fluentdみたいなログエージェントとか）から成ります。サブのコンテナをサイドカーと言います。  

Serviceは、[公式ドキュメント](https://kubernetes.io/ja/docs/concepts/services-networking/service/)によると

> Podの集合で実行されているアプリケーションをネットワークサービスとして公開する抽象的な方法です。

らしいです。  
こいつはアプリケーションをクラスタの外に公開したり、クラスタ内でアプリケーション同士が協調するためのお膳立てをしたりしてくれます。すなわちアプリケーションにエンドポイント（仮想IP）を与えて通信を成立させるわけですね。しかもそのエンドポイントはクラスタ内で勝手に動いているDNSに登録されるようになっています。```kubectl cluster-info```で見える謎のDNSくんはServiceのためのコンポーネントだったんですね。  
クラウド環境だとクラウドプロバイダが提供するロードバランサをServiceとして使えるらしいですが、手元で遊んでるだけの僕は関係ないのでパスします。MetalLB？アハハ！

Nodeですがこれは一番簡単で、Podが走るマシンのことです。仮想マシンでも物理マシンでもどっちでもOKですが、今回のケースでは仮想マシンですね。  
ところで、ここを逃すとおそらく言及する機会がないので言及しますが、実はすべてのノード（マスターノード、ワーカーノード）上で[動いている人たちがいます](https://kubernetes.io/ja/docs/concepts/overview/components/#node-components)、kubeletはコンテナが動いているか監視してくれます。kube-proxyはNode内のネットワークをいい感じにしてくれて、この人のおかげでPodへの（クラスタ内/外両方からの）アクセスが実現している（＝Serviceという抽象的な機能の一部を担当している）ようです。  
コンテナの実行を担当するコンテナランタイムくんはちょっと前に話題になりましたね。Kubernetes 1.20からコンテナランタイムにDockerを使うのが非推奨に、1.24に至っては完全に使えなくなりました。現在は主にcontainerdが使われていまして、それを確認することもできます。適当にクラスタを立ち上げて
```bash
kubectl describe node | grep Container
```
を打つと
```bash
    Container Runtime Version:  containerd://1.5.10
```
このとおりわかります。
### クラスタの設定
kindではマルチノードなクラスタを立てることができます。せっかくなので、マスターノードとワーカーノードを別で立ててみましょう。
クラスタのマニフェストは以下のようになります。
```yaml
# cluster.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: hello-world #クラスタ名
nodes:
  - role: control-plane
  - role: worker
    extraPortMappings:
    - containerPort: 30001 #ServiceでNodePortとして開放するポート
      hostPort: 8000 #ホスト向けに公開するポート
      protocol: TCP
```
extraPortMappingsに関して、containerPort/hostPortはServiceとホストを繋げるための設定です。このケースでは30001番で動いているServiceをホストの8000番につなげます。
apiVersionは何も考えず写経しました。こいつだけは何をもって決めるのか一切わかりません。あとは見たまんまですね。nodesのroleを増やせばNodeが増えます。
```bash
kind create cluster -f cluster.yaml
```
でクラスタを立ち上げられます。この時点では、このクラスタは無です（まぁコントロールプレーンには4つのPodがありますが……）。

### Podの設定
今回のようにちょろっとNginxを走らせたいというだけであれば、Podの中身はnginxのコンテナ1つだけで事足ります（ただし、例えばログをきっちり管理したい場合、ログ基盤に転送するためのサイドカーをつけたりするはず）。
というわけでPodのマニフェストは以下のようになります。
```yaml
# nginx.yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx #Pod名
  labels:
    app: nginx #key,valueともに何でもよい。Serviceのselectorフィールドで再び登場する。
spec:
  containers:
    - name: nginx
      image: nginx:latest
```
ラベルは、Kubernetesのオブジェクトを選択するために使います。今回はServiceが公開するPod（∈オブジェクト）を選択するのに使います。本番環境用のPodを選択したい場合、```env:prd```みたいなキーをつけると選択するときに便利そうですね。まぁ実務経験ないから知らんけど。  
specにはPodの中身、つまりコンテナ（と永続化が必要な場合はボリューム）の情報が記述されます。  
というわけで、上述のマニフェストを使ってnginx用のPodをワーカーノードに生やしてあげましょう。そのためのコマンドが```kubectl apply```です。
```bash
$ kubectl apply -f nginx.yaml
pod/nginx created
```
これでnginxが走るPodを起動できました。最後に、このPodをクラスタの外部（=ホストの8000番）に公開するための設定をすればクリアです。
（ちなみに、PodをPod単体で起動するとオートヒーリングが効かないので、次回紹介するReplicaSetやDeployment、というか[大抵Deploymentのみを使うことが推奨されます](https://kubernetes.io/ja/docs/concepts/workloads/controllers/replicaset/#replicaset%E3%82%92%E4%BD%BF%E3%81%86%E3%81%A8%E3%81%8D)。ざっくりいうとReplicaSetはPodを冗長化して管理するもの、DeploymentはReplicaSetを管理するものです。）  

## Serviceの設定
Serviceのマニフェストはこちらです。
```yaml
#service.yaml
apiVersion: v1
kind: Service
metadata:
  name: hello-service #service名
spec:
  type: NodePort
  selector:
    app: nginx # 公開したいpodのラベル（pod用のmanifestで設定したlabelのKeyとValueが一致するもの）
  ports:
    - port: 80 #内部で使うポート
      nodePort: 30001 #クラスタの外からアクセスするときに使うポート
      protocol: TCP
```
ここでselectorとしてさっきのPodにつけたラベルの```app:nginx```が出てきましたね。これは```app:nginx```のラベルがついているPod全体の集合を並列に展開されたサービスとみなしてその窓口になる仮想IPを作って負荷分散するというものでしょう（TODO:これが嘘か本当か調べる）。これ全然違うPodでラベルが重複したらヤバいことになりそうですね。  
portに関しては、ここでは省略しているフィールドが関連していて、説明しづらいので一旦パスです。  
ところで、僕はこの記事を書いていてnodePortに関して強烈な違和感を覚えました。  
クラスタの外からアクセスするための仕組みがそもそもあるなら、クラスタのマニフェストで謎のマッピングなんかせずにこれを使ってアクセスすればいいじゃないですか。  
NodePortの使い方は<任意のNodeのIP>:<NodePort\>って[書いてました](https://kubernetes.io/ja/docs/concepts/services-networking/service/#publishing-services-service-types)。どのNodeに出してもクラスタ内で適切に回してくれるみたいですね。その代わり、異なる二つのNodeで同じポート番号を別の用途に使おう！ということはできないようです。それができる嬉しさは特に思いつかないですが。
さて、NodeのIPを確認するには
```bash
kubectl describe node
```
でOKです。結果は
```
...
Addresses:
  InternalIP:  172.21.0.2
  Hostname:    hello-world-worker
...
```
＿人人人人人人人人人人人＿  
＞　Internal IPしかない　＜  
￣Y\^Y\^Y\^Y\^Y\^Y\^Y\^Y\^Y\^Y\^Y\^￣  
Internal IPしかないということはNodeが外部に公開されていないということで、つまりNodePortによるクラスタ外からのアクセスは不可能ということです。
怒りのあまりk8sのリポジトリにissueを2億個ぐらい立ててやろうかと思いましたが、すんでのところでNodeに関する[公式ドキュメント](https://kubernetes.io/ja/docs/concepts/architecture/nodes/#addresses)を読みました。

> これらのフィールドの使い方は、お使いのクラウドプロバイダーやベアメタルの設定内容によって異なります。  

ウー

**追記1**
kindの[LoadBalancerのページ](https://kind.sigs.k8s.io/docs/user/loadbalancer/)に

>With Docker on Linux, you can send traffic directly to the loadbalancer's external IP if the IP space is within the docker IP space.  
>On macOS and Windows, docker does not expose the docker network to the host. Because of this limitation, containers (including kind nodes) are only reachable from the host via port-forwards, ...(以下略)

って書いてました。特定OS上のDockerの挙動からくる問題みたいですね。WindowsやMacを使うときは覚えておくといいかも。


ドンマイ。  
気を取り直してserviceを起動しましょう。
```
$ kubectl apply -f service.yaml
service/hello-service created
```
これでやることは全て終わったので、```localhost:8000```へアクセスすると。Nginxのいつものアレが見られるはずです。
ダメだった場合、コピペをミスったか、この記事が古すぎてKubernetesが別時空の存在になってしまったか、環境構築が失敗していると思います。
とりあえず```kubectl get pods```や```kubectl get svc```や```kubectl get event```で怪しげなエラーが起きていないか見てみましょう。

## お気持ち
これホストにNodePort繋げてるNodeが沈んだら終わりじゃね？

## お片付け
```bash
kind delete cluster --name=hello-world
```


## 次回予告
* ReplicaSetとDeploymentやる  
* HPAもやる


これにておしまい。