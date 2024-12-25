## Please patch 

Due to PVC in pending state error (**violates PodSecurity "baseline:latest" **) [FIX](https://github.com/rook/rook/issues/11755#issuecomment-1444957300)

```kubectl label ns local-path-storage pod-security.kubernetes.io/enforce=privileged```
