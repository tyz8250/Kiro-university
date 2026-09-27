```
Mac
 ↓
Internet
 ↓
IGW
 ↓
Route Table
  0.0.0.0/0 → IGW
 ↓
EC2
 ↓
Docker
 ↓
Go
```

curl http://<public-ip>:8080 が成功している。


## Experiment 1: Route Table の default route を削除する

### Change
Public Subnet の Route Table から

0.0.0.0/0 → Internet Gateway

を削除する。

### Hypothesis

#### ① Mac の curl
失敗する。

理由：
EC2からMacへ返す通信をInternet Gatewayへ送るルートがなくなるため、
HTTPレスポンスを返せないと予想する。

#### ② EC2 の tcpdump
Macから送ったTCP SYNは見えないと予想する。

理由：
Route TableからInternet Gatewayへの経路がなくなることで、
InternetからEC2までパケットが届かなくなると考えている。

#### ③ Go / Docker
正常時と同じようには動作しないと予想する。

理由：
外部から通信が届かなくなるため、
GoやDockerも処理を開始できないと考えている。

## Experiment 2: Docker port mapping を削除する

### Change
`docker run -p 8080:8080 ...`

から `-p 8080:8080` を削除する。

### Hypothesis

#### ① Mac の curl
失敗する。

予想：
port mapping がないため、Docker内のGoまで通信が届かず、
Goも正常に処理できないと考えている。

#### ② EC2 の tcpdump
TCP SYN は見える。

理由：
AWSのRoute TableやEC2自体は正常なので、
Macからの通信はEC2までは届くと考えている。

#### ③ Container内部の curl
`curl localhost:8080` も失敗すると予想する。

理由：
port mapping がないことで、
Container内のGoも動作しないと考えている。

## Experiment 3: Goを127.0.0.1にbindする

### Change
0.0.0.0:8080 → 127.0.0.1:8080

### Hypothesis

① Macからのcurl
→ 返ってこない

② EC2のtcpdump
→ TCP SYNは見える

③ Container内部のcurl localhost:8080
→ 成功する

