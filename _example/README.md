# Esempio di applicazione con kind
In questo esempio si utilizza un'installazione locale kind per testare lo scheduler in ogni suo componente.

## Sommario
- [Sostituzione del Kernel WSL (Opzionale, solo per Windows)](#Sostituzione-del-Kernel-WSL-(Opzionale,-solo-per-Windows))
- [Build delle immmagini](#Build-delle-immagini)
- [Installazione di Kind](#Installazione-di-Kind)
- [Deployment del Descheduler](#Deployment-del-Descheduler)
- [Modifica del Default Scheduler](#Modifica-del-Default-Scheduler)
- [Deployment di Probe e Target](#Deployment-di-Probe-e-Target)
- [Esecuzione del Sistema](#Esecuzione-del-Sistema)

## Sostituzione del Kernel WSL (Opzionale, solo per Windows)
Per introdurre un ritardo sulle richieste è possibile utilizzare il comando `tc`
~~~
tc qdisc add dev eth0 root netem delay 100ms
~~~
Di default il kernel WSL2 fornito da Microsoft non ha il module `netem` abilitato, necessario per l'utilizzo del comando `tc`.
È necessario ricompilare il kernel di linux come indicato in [questa guida](https://learn.microsoft.com/en-us/community/content/wsl-user-msft-kernel-v6) impostando il flag `CONFIG_NET_SCH_NETEM=y` nel file `Microsoft/config-wsl`.
Nell'unico test effettuato sono state anche inserite le flag indicate in [questa](https://github.com/microsoft/WSL/issues/6065) pagina.
N.B: eventuali ripetizioni di flag anche se precedute dal carattere `#` generano un errore: ogni flag deve comparire una ed una sola volta.

Nella directory [`/wsl-kernel-netem`](https://github.com/role-nzo/K8sLatencyBasedScheduler/tree/master/wsl-kernel-netem) sono disponibili due kernel pronti per l'utilizzo col modulo abilitato.

## Build delle immmagini
Prima di procedere è necessario buildare le immagini di tutti i componenti del sistema: `lm-server`, `lm-client`, `descheduler` e `kube-scheduler`.
Le istruzioni possono essere trovate nei rispettivi repository:
- [latency-meter](https://github.com/role-nzo/latency-meter/)
- [descheduler](https://github.com/role-nzo/descheduler/)
- [scheduler-plugins](https://github.com/role-nzo/scheduler-plugins/)

## Installazione di Kind
Per installare Kind, seguire le istruzioni disponibili sul sito ufficiale: [Kind Installation](https://kind.sigs.k8s.io).

Dopo l'installazione è possibile creare un cluster utilizzando il file [`/_example/kind-multi-node-config.yaml`](https://github.com/role-nzo/K8sLatencyBasedScheduler/tree/master/_example/kind-multi-node-config.yaml) utilizzando il comando
~~~
kind create cluster --name <NOME_CLUSTER> --config=kind-multi-node-config.yaml
~~~

Per rendere i test più efficaci si consiglia di inserire un ritardo crescente sui vari nodi utilizzando il comando `tc`.
Nell'i-esimo nodo eseguire (sostituire `<i>` con l'indice del nodo):
~~~
tc qdisc add dev eth0 root netem delay <i>00ms
~~~

In alternativa, è possibile impostare una latenza elevata su tutti i nodi tranne uno, forzando così lo scheduler a scegliere il nodo con la latenza minore.

## Deployment del Descheduler
Per il deployment del descheduler, copiare i file nella directory [`/config`](https://github.com/role-nzo/descheduler/tree/master/config) (repository [`descheduler`](https://github.com/role-nzo/descheduler/)) e applicarli sul control node con i seguenti comandi:
~~~
kubectl apply -f rbac.yaml
kubectl apply -f deployment.yaml
~~~
Assicurarsi di specificare l'immagine Docker e la sua versione nel file di deployment prima dell'uso.
Il descheduler sarà schedulato sul control node. Per tutti i parametri disponibili consultare il repository [`descheduler`](https://github.com/role-nzo/descheduler/).

## Modifica del Default Scheduler
Sul control node modificare il file in `/etc/kubernetes/scheduler-config.yaml` col contenuto disponibile in [`/manifests/latencyaware/scheduler-config.yaml`](https://github.com/role-nzo/scheduler-plugins/tree/master/manifests/latencyaware/scheduler-config.yaml) nel repository scheduler-plugins. Questo informerà lo scheduler su quali plugin utilizzare e quali evitare. Un esempio già configurato è disponibile in questa directory: [`/_example/scheduler-config.yaml`](https://github.com/role-nzo/K8sLatencyBasedScheduler/tree/master/_example/scheduler-config.yaml).

Successivamente modificare il file `/etc/kubernetes/scheduler-config.yaml` nel control-node inserendo l'immagine appena buildata di [scheduler-plugins](https://github.com/role-nzo/scheduler-plugins/).

## Deployment di Probe e Target
Infine, sempre nel control node, effettuare il deployment del servizio `target` (ad esempio `nginx`) con i `probe`, necessari per il corretto funzionamento dello scheduler.

Copiare il file [`/_example/complete-deployment.yaml`](https://github.com/role-nzo/K8sLatencyBasedScheduler/tree/master/_example/complete-deployment.yaml) nel control node ed eseguirlo con:
~~~
kubectl apply -f complete-deployment.yaml
~~~
Questo inizializzerà i pod in modo tale che ogni container `target` sarà affiancato da un container `probe`. Inoltre, verrà creato un ulteriore pod contenente solo un container `probe`, necessario per il corretto funzionamento dello scheduler.

I servizi saranno esposti utilizzando:
- il file [`/config/lm-server-service.nodeport.yml`](https://github.com/role-nzo/latency-meter/tree/master/config/lm-server-service.nodeport.yml) nel repository latency-meter per i container `probe`
- il file di esempio [`/_example/service-target.yaml`](https://github.com/role-nzo/K8sLatencyBasedScheduler/_example/service-target.yaml) per i container `target` (`nginx` nel nostro caso)

## Esecuzione del Sistema
- copiare il file `/etc/kubernetes/admin.conf` nella macchina host
- avviare il programma [`/_example/tester.sh`](https://github.com/role-nzo/K8sLatencyBasedScheduler/_example/tester.sh) nel control-node per misurare la latenza verso il servizio `target`
- sulla macchina host, eseguire il seguente comando per avviare il servizio che pubblicherà i dati su un server MQTT, informando così il descheduler:
~~~
docker run --network kind --rm -v <percorso_host_al_file_admin.conf>:/root/kubeconfig lm-client:5 -kubeconfig=/root/kubeconfig -lmport=30007
~~~