## Please patch due to PVC in pending state error ( violates PodSecurity "baseline:latest" )

```kubectl label ns local-path-storage pod-security.kubernetes.io/enforce=privileged```
