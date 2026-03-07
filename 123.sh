cd /Users/wei/edgetunnel/CFWarpXray

docker build -t cfwarpxray .

docker rm -f cfwarpxray
docker run -d --name cfwarpxray \
  --restart unless-stopped \
  --dns 1.1.1.1 \
  --dns 8.8.8.8 \
  --cap-add=NET_ADMIN --cap-add=NET_RAW --cap-add=MKNOD \
  --device-cgroup-rule 'c 10:200 rwm' \
  --sysctl net.core.somaxconn=65535 \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  --sysctl net.ipv4.ip_forward=1 \
  -p 16666:16666 -p 16667:16667 \
  cfwarpxray

  docker run -d --name cfwarpxray \
    --restart unless-stopped \
    --dns 1.1.1.1 \
    --dns 8.8.8.8 \
    --cap-add=NET_ADMIN --cap-add=NET_RAW --cap-add=MKNOD \
    --device-cgroup-rule 'c 10:200 rwm' \
    --sysctl net.core.somaxconn=65535 \
    --sysctl net.ipv4.conf.all.src_valid_mark=1 \
    --sysctl net.ipv4.ip_forward=1 \
    -p 16666:16666 -p 16667:16667 \
    cfwarpxray

cd /Users/diannao/edgetunnel/CFWarpXray
docker build -t cfwarpxray .
docker rm -f cfwarpxray 2>/dev/null
docker run -d --name cfwarpxray \
  --restart unless-stopped \
  --dns 1.1.1.1 \
  --dns 8.8.8.8 \
  --cap-add=NET_ADMIN --cap-add=NET_RAW --cap-add=MKNOD \
  --device-cgroup-rule 'c 10:200 rwm' \
  --sysctl net.core.somaxconn=65535 \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  --sysctl net.ipv4.ip_forward=1 \
  -p 16666:16666 -p 16667:16667 \
  cfwarpxray

  docker stop cfwarpxray
  docker rm cfwarpxray



  vless://a1b2c3d4-e5f6-7890-abcd-ef1234567890@127.0.0.1:16666?encryption=none#CFWarpXray