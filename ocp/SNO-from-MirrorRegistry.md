## SNO from Mirror Registry

- Download tools

```
dnf install /usr/bin/nmstatectl -y
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.18.30/openshift-install-linux.tar.gz
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/4.18.30/openshift-client-linux.tar.gz
tar zxvf openshift-install-linux.tar.gz
tar zxvf openshift-client-linux.tar.gz
mv oc /usr/local/bin/
mv kubectl /usr/local/bin/
rm openshift-install-linux.tar.gz openshift-client-linux.tar.gz README.md
```

- Transfer merged-pull-secret file (/home/cloudcafe/merge-pull-secret) from Mirror Registry server

```
scp cloudcafe@192.168.1.150:/home/cloudcafe/merge-pull-secret .
cp merge-pull-secret pull-secret
```
  
- Preparation

```
ssh-keygen -t rsa -N '' -f cloudcafe

ISO_URL=$(./openshift-install coreos print-stream-json | jq -r '.architectures.x86_64.artifacts' | grep location | grep iso | cut -d\" -f4)
PULLSECRET=`cat pull-secret` 
SSHKEY=`cat cloudcafe.pub`

echo $ISO_URL
echo ""
echo $PULLSECRET
echo ""
echo $SSHKEY

mkdir ocp418
mkdir ocp418-backup

cat << EOF > agent-config.yaml
apiVersion: v1beta1
kind: AgentConfig
metadata:
  name: sno-sa
rendezvousIP: 192.168.1.140
hosts:
  - hostname: master-0
    interfaces:
      - name: enp1s0
        macAddress: 52:54:00:42:a4:40
    rootDeviceHints:
      deviceName: /dev/vda
    networkConfig:
      interfaces:
        - name: enp1s0
          type: ethernet
          state: up
          mac-address: 52:54:00:42:a4:40
          ipv4:
            enabled: true
            address:
              - ip: 192.168.1.140
                prefix-length: 24
            dhcp: false
      dns-resolver:
        config:
          search:
            - pkar.tech
          server:
            - 192.168.1.161
            - 192.168.1.1
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: 192.168.1.1
            next-hop-interface: enp1s0
            table-id: 254
EOF

cat << EOF > install-config.yaml
apiVersion: v1
baseDomain: pkar.tech
compute:
- architecture: amd64
  name: worker
  replicas: 0
controlPlane:
  architecture: amd64
  name: master
  platform:
  replicas: 1
metadata:
  name: sno-sa
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 192.168.1.0/24
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
pullSecret: '$PULLSECRET'
sshKey: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDFoML+fLuVqwcWbtH6TGiq9VxIUi0umNaJAEVixhTLhiAnHEk8OT8p06fFxYAM+1B+oMPfU5u/36+gWIrTPUD+jgzdEZksZ8BoHveDOrrJBEGWD4xsVGj7szV4bXBEHbxgD4WeILIAtYy/QMaH+Nxkdj/eUoD7KYSelNkwKPJpJkbTIzQs6r76VYYxQkeGbraRJ5EnGQWjeAVqXXlCvzssJxGbEagub3cmv99niCa3EfUd6fPS4OjqYI7SkYSdJezRHJ5Q+eLuqTG5oicD8MWbWMsEvPC97n9bmqLsrfh1g+K69eE92a2Gu6kSwZIMcdbktEBeEeUDz/lgVG1+y/z4JFB57dSVxtdYrawxFMvVNVmX1XXydkQzOJU7WQ3Wm55qS8Zv9vCEmu9hEdZ0AC3+5pFktprNj861ETiKs969HG/xIZxUqvmWVJQI9c9eIo1KF7wxEav5VvCxV4yZq7ulUjkuMOZIPvqyWIbjz1kwFmXU9k1Ihi4gUsnKA94eKpU= root@lenevo-ts-w2
additionalTrustBundle: |
  -----BEGIN CERTIFICATE-----
  MIIDpzCCAo+gAwIBAgIUMo+eBh/XOUjfjb9VTu6lOr2HDbcwDQYJKoZIhvcNAQEL
  BQAwczELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAlZBMREwDwYDVQQHDAhOZXcgWW9y
  azENMAsGA1UECgwEUXVheTERMA8GA1UECwwIRGl2aXNpb24xIjAgBgNVBAMMGW1p
  cnJvci1yZWdpc3RyeS5wa2FyLnRlY2gwHhcNMjYwMTA4MTQwOTQ1WhcNMjYxMjMw
  MTQwOTQ1WjAaMRgwFgYDVQQDDA9xdWF5LWVudGVycHJpc2UwggEiMA0GCSqGSIb3
  DQEBAQUAA4IBDwAwggEKAoIBAQDcCB9hauTmHbTOSGp26tNXH/Cz3NrZ72qlko01
  LqCWkLDMRMTzo7t1R21ClEhtyKRyEJFQPer1EFauHrkymWdxB5ruUYHAnpf5lIbd
  em03brgqkuaXicXvs5gtPEayZiv0X8xLM3LVy8hrjWOnST5cD4shqieZISQfPNI8
  9+2F87U9LfnyYNjSNZ0LklxEATzrskBqCzT9BBcqcV9GTr07mpshI1tZLUCSU3pv
  cSSBy8r1k0hoNeTnQDgHlNgKttgthuoTH+cq4Za72jit2f7/wKZTzQQrEJFJfqCv
  SKig0eu6v4859vYCYn5iXXm0QE0Ck3hJRa31N3vOTy9vSgsnAgMBAAGjgYswgYgw
  CwYDVR0PBAQDAgLkMBMGA1UdJQQMMAoGCCsGAQUFBwMBMCQGA1UdEQQdMBuCGW1p
  cnJvci1yZWdpc3RyeS5wa2FyLnRlY2gwHQYDVR0OBBYEFC3T+oKBnU3rweBFbAeb
  O7xROmytMB8GA1UdIwQYMBaAFH/E3ISB2jFNsYrQO/Fih1szYuqjMA0GCSqGSIb3
  DQEBCwUAA4IBAQAziOzzPwFG9/gQOJgOvBNXi2FNi7EQ4SUwgjkWNPlwllC4bywG
  xNpFvGdQiu115okaiTibzatoPXIqRmj9QcrV68qEYGPSf8mfWCOfahO++s4g2e1b
  CYB1KKP5Wv7A1bBT0ipx3YYKkR7og2jtVQtBsLj8gDzPTGNjXtotF25+53CAJ6Wt
  JK+rn58IakUZgXr5Owg7hlz/tXlDgfUbIWT0icOrwU+rLhVtuFTcpFIcZzljznI4
  IIrBSXYyTXs+Pushk6hZOPl7pwDePrcFbgRGyXTHHWz+kcxOi0pX2eKTXIoCUrW5
  MlOlyD/xGV5pepYhPo5CkJ12UAkmo+QPaMHW
  -----END CERTIFICATE-----
  -----BEGIN CERTIFICATE-----
  MIID8TCCAtmgAwIBAgIUTtDLZ0pCIL/VqsOsNJ3Z/I0pYe8wDQYJKoZIhvcNAQEL
  BQAwczELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAlZBMREwDwYDVQQHDAhOZXcgWW9y
  azENMAsGA1UECgwEUXVheTERMA8GA1UECwwIRGl2aXNpb24xIjAgBgNVBAMMGW1p
  cnJvci1yZWdpc3RyeS5wa2FyLnRlY2gwHhcNMjYwMTA4MTQwOTQzWhcNMjgxMDI4
  MTQwOTQzWjBzMQswCQYDVQQGEwJVUzELMAkGA1UECAwCVkExETAPBgNVBAcMCE5l
  dyBZb3JrMQ0wCwYDVQQKDARRdWF5MREwDwYDVQQLDAhEaXZpc2lvbjEiMCAGA1UE
  AwwZbWlycm9yLXJlZ2lzdHJ5LnBrYXIudGVjaDCCASIwDQYJKoZIhvcNAQEBBQAD
  ggEPADCCAQoCggEBAI28UiCa+Iv0WJZQ/9u/6zwEfobncWfbsxZG8bhhFHsHSrwU
  /NhjBS1QDoPDPoOoL1Lg4S712oLtMAVVOnyHLTIIoLVjZ0i4Fc2q4TRIoppE1f6z
  COGjhgL0q5IVBTL3ZtkX75B/wl4wHW9XZ+hiRXf+2jRYbUUSylcCQ3dDntE14tfl
  7WXfn1hVcoOHfuirq8PgfiVLCr1pL2s0NZnynodscgLC4uBTG84SI0CGZGckI9SR
  TAaN+f6CmHJ7UoYMeffHi9QM9ogDRcKHwTKXNGQ5dUpgbm7HSIo45xmBBGb3Oxjb
  7SUXO5aM5GzOrMqxAXEcyTe2pID7TgMXDaLO/CkCAwEAAaN9MHswCwYDVR0PBAQD
  AgLkMBMGA1UdJQQMMAoGCCsGAQUFBwMBMCQGA1UdEQQdMBuCGW1pcnJvci1yZWdp
  c3RyeS5wa2FyLnRlY2gwEgYDVR0TAQH/BAgwBgEB/wIBATAdBgNVHQ4EFgQUf8Tc
  hIHaMU2xitA78WKHWzNi6qMwDQYJKoZIhvcNAQELBQADggEBAFLj4wT7t6vtNl9c
  e1M58YOcAjjN/Pz0Aw5Rrxf36JO1ZnFT/yKVxDMhfvV4C3hGMWIiaHymap2yTZxZ
  ozAGMMiXps3+EjEAfWTlQcSosm8pkY51+oWpUo5Z/QtmwuQ7PtQ1sI8so+8rRBqH
  6qyVsmBI82RrbeMvBzARHa1Va2jov76KXLwsXnDvzQkzfW+nB0Ea/Wo1HlyKzRQC
  x4mSEOfY2Z75pBdjMnmD2cRt4JR/10aV10rot6TSXHqOIcA9XZ1A9Vr1anve5N/2
  Rzk8jcVj7c5OKWTOSXhyspsKk9JUS9PLdv+rFEuDTgzfZ6NYB6YBhZAHz9gkohgi
  TGaluAY=
  -----END CERTIFICATE-----
imageDigestSources:
- mirrors:
  - mirror-registry.pkar.tech:8443/ocp/openshift/release
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
- mirrors:
  - mirror-registry.pkar.tech:8443/ocp/openshift/release-images
  source: quay.io/openshift-release-dev/ocp-release
EOF


cp *-config.yaml ocp418-backup/
cp *-config.yaml ocp418/
```

- Create iso

```./openshift-install --dir=ocp418 agent create image --log-level=debug ```

- Create VM using ISO

```
qemu-img create -f qcow2 /home/sno/sno-sa.qcow2 120G

virt-install \
  --name=sno-sa \
  --ram=16384 \
  --vcpus=12 \
  --cpu host-passthrough \
  --os-variant=rhel8.0 \
  --noreboot \
  --events on_reboot=restart \
  --noautoconsole \
  --import \
  --cdrom /home/sno/standalone/ocp418/agent.x86_64.iso \
  --disk path=/home/sno/sno-sa.qcow2,size=120 \
  --network network=host-bridge,mac=52:54:00:42:a4:40 \
  --graphics vnc,listen=0.0.0.0,port=5979,password=pkar2675
```

- Monitor install boostrapping

```openshift-install --dir=ocp418 agent wait-for bootstrap-complete --log-level=debug```

- Verify install complete

```openshift-install --dir=ocp418 agent wait-for install-complete --log-level=debug```

- Login Cluster

```
export KUBECONFIG=/home/sno/standalone/ocp418/auth/kubeconfig
oc get no
oc get co
```

