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
