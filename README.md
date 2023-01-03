# Postgres Forward Pod

## Prerequisites

### Acquiring OTC credentials

Clone the [platform repository](https://github.com/digitalservicebund/platform).

Follow the section:
- "[Getting access to the Open Telekom Cloud for the first time](https://github.com/digitalservicebund/platform/blob/main/terraform/README.md#getting-access-to-the-open-telekom-cloud-for-the-first-time)"

### Seting up kubeconfig

Follow these sections:
- "[Setting up your credentials to run terraform](https://github.com/digitalservicebund/platform/blob/main/terraform/README.md#setting-up-your-credentials-to-run-terraform)"
- and in "[Generate your kubeconfig file](https://github.com/digitalservicebund/platform/blob/main/terraform/README.md#generate-your-kubeconfig-file)"

Now you can run the command to check how you desired namespace is called, this is needed later on:

```bash
# example path for kubeconfig-file: ~/.kube/otc-dev
kubectl --kubeconfig <kubeconfig-file> get namespaces
```

## Set up a forwarder-pod
This will create a new pod with the sole purpose to connect to the database via port forwarding from local to this pod:

```bash
export NAMESPACE=...
# find this value either in the database configuration in Argo CD or via inspecting the output of 'kubectl --kubeconfig <kubeconfig-file> -n <namespace> describe configmap'
export DATABASE_HOST=...

# cd into this repository

# create the pod
envsubst < manifest.yaml | kubectl apply -n $NAMESPACE -f -

# port mapping example: 5000:5432
kubectl --kubeconfig <kubeconfig-file> port-forward postgres-forward-pod <local-port>:<remote-port> -n $NAMESPACE
```

## Connect to the database

Now you need to retrieve the username and password to access the database via the forwarded port:

```bash
# see available secrets
kubectl --kubeconfig <kubeconfig-file> -n <namespace> get secret
# use the desired secret name to retrieve it
kubectl --kubeconfig <kubeconfig-file> -n <namespace> get secret <secret-name> -o jsonpath='{.data}'
```

This gives you something like: `{"db.password":"","db.user":""}`, which now needs to be decoded:

```bash
echo "<db.user>" | base64 --decode
echo "<db.password>" | base64 --decode
# note that the last "%" is not part of the decoded string
```

Now you have the credentials and can connect to the database by using the UI in IntelliJ or via command line: 

```bash
# 'brew install postgresql' if you don't have psql yet
# example for local-port from above: 5000
PGPASSWORD=<password> psql -U <username> -h localhost -d <databasename> -p <local-port>
```

## Shut down the forwarder-pod
Once you are done, it's important you remember to shut down the pod you created:

```bash
envsubst < manifest.yaml | kubectl --kubeconfig <kubeconfig-file> delete -n $NAMESPACE -f -
```
