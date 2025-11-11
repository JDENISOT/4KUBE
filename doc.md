# 4KUBE D0CUMENTATION
## 1 Création du cluster

### Instalation de Kind

#### Linux
```bash
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-$(uname)-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind
```

#### Windows (PowerShell) : 
```bash
choco install kind
```
#### macOS : 
```bash
brew install kind
```

### Pourquoi Kind?

Nous avons choisi d'utiliser la technologie Kind car elle nous permet de créer des vraies noeuds, pour créer le cluster demandé via un seul fichier config. Cette solution nous permet aussi de travailler vraiment en groupe, pas besoin d'envoyer les disques de vm. De plus nous pouvons vous envoyez notre configuration du cluster. Kind sert a simuler un cluster multi-nœuds localement,
ce qui répond à la contrainte d’un cluster “autre que Docker Desktop / Minikube”.

PI, nous orions aussi pu utiliser K3d

### Définir le cluster

pour créer le cluster rien de plus simple, il faut créer le fichier `kind-config.yaml` il devra se trouver au même niveau que notre dossier `k8s/`


kind-config.yaml:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: fleetman
nodes:
  - role: control-plane
    # On mappe les NodePorts vers la machine hôte pour accéder en localhost
    extraPortMappings:
      - containerPort: 30080   # trucks-web-app (NodePort 30080)
        hostPort: 30080
        protocol: TCP
      - containerPort: 30020   # trucks-api-gateway (NodePort 30020)
        hostPort: 30020
        protocol: TCP
  - role: worker
  - role: worker
networking:
  # Laisser par défaut; Kind fournit un CNI fonctionnel
  disableDefaultCNI: false
  kubeProxyMode: "iptables"
```


On n’a pas besoin d’installer un CNI (Calico/Flannel) avec Kind, il est déjà OK.
On pense a mapper les port afins de pouvoir accéder au site depuis notres hôte

ici on a défini 3 noeuds, 1 master et 2 worker

### Déployer le cluster

Pour déployer le cluster il faut taper cette comande:

```bash
kind create cluster --config kind-config.yaml
```
pour vérifier le déployment de ce dernier:

```bash
kubectl cluster-info
kubectl get nodes -o wide
```

exemple de sortie:

![Cluster deployment check](src/capture-check-deployer.png)

attention ici no worker ont pour rôle `none`ça ne veux pas dire qu'il ne sont pas des worker

pour la lisibilité nous pouvons ajouter manuellement un rôle aux nœuds si tu veux que la colonne soit plus parlante :
```bash
kubectl label node fleetman-worker  node-role.kubernetes.io/worker=worker
kubectl label node fleetman-worker2 node-role.kubernetes.io/worker=worker
```

ce qui donne 

```bash
kubectl get nodes -o wide 

NAME                     STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION     CONTAINER-RUNTIME
fleetman-control-plane   Ready    control-plane   13m   v1.31.0   172.18.0.2    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://1.7.18
fleetman-worker          Ready    worker          13m   v1.31.0   172.18.0.4    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://1.7.18
fleetman-worker2         Ready    worker          13m   v1.31.0   172.18.0.3    <none>        Debian GNU/Linux 12 (bookworm)   6.10.14-linuxkit   containerd://1.7.18
```

----

Nickel, ta partie “1 Création du cluster” est déjà propre 👌
Je te propose d’enchaîner directement avec la suite logique du sujet : passer de la stack Docker Compose fournie dans l’énoncé à une série de manifests Kubernetes. Je te l’écris dans le même style que toi, en français, et tu pourras le coller à la suite.

---

## 2 Déploiement de l’application Fleetman dans Kubernetes

Dans le sujet, l’application est fournie sous forme de `docker-compose.yml` avec plusieurs services (`queue`, `position-simulator`, `position-tracker`, `api-gateway`, `webapp`, `mongodb`).
En Kubernetes, on va faire **1 Deployment + 1 Service** par composant (sauf cas particulier) pour bien isoler les rôles.

> ⚠️ Le sujet demande aussi de changer le profil Spring et une image de la web app. On l’intègre directement dans les manifests.

### 2.1 Rappel des adaptations à faire

* Dans les conteneurs Spring Boot (simulator, tracker, api-gateway), remplacer :

  ```text
  SPRING_PROFILES_ACTIVE=local-microservice
  ```

  par :

  ```text
  SPRING_PROFILES_ACTIVE=production-microservice
  ```

* Pour la web app, utiliser l’image :

  ```text
  supinfo4kube/web-app:1.0.0
  ```

  (et non `...-dockercompose`)

* On expose en **NodePort** ceux qu’on veut atteindre depuis l’hôte (déjà mappés dans le `kind-config.yaml` au §1) :

  * web app → 30080
  * api gateway → 30020

Ainsi Kind route vers le cluster, et le service NodePort route vers le pod.

---

### 2.2 Namespace (optionnel mais propre)

On peut mettre toute l’app dans un namespace dédié, par ex. `fleetman` :

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: fleetman
```

Appliquer avant le reste :

```bash
kubectl apply -f k8s/namespace.yaml
```

---

### 2.3 MongoDB (avec persistance)

Mongo est la seule brique qui doit **garder des données**. Même si Kind est éphémère, ici le but est de montrer qu’on sait faire.

```yaml
# k8s/mongodb.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mongodb-pvc
  namespace: fleetman
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fleetman-mongodb
  namespace: fleetman
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fleetman-mongodb
  template:
    metadata:
      labels:
        app: fleetman-mongodb
    spec:
      containers:
        - name: mongodb
          image: mongo:3.6.23
          ports:
            - containerPort: 27017
          volumeMounts:
            - name: mongo-data
              mountPath: /data/db
      volumes:
        - name: mongo-data
          persistentVolumeClaim:
            claimName: mongodb-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: fleetman-mongodb
  namespace: fleetman
spec:
  selector:
    app: fleetman-mongodb
  ports:
    - name: mongo
      port: 27017
      targetPort: 27017
  type: ClusterIP
```

Ici on met `ClusterIP` parce que Mongo n’a pas besoin d’être accessible depuis l’extérieur.

---

### 2.4 File de messages (ActiveMQ)

```yaml
# k8s/queue.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fleetman-queue
  namespace: fleetman
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fleetman-queue
  template:
    metadata:
      labels:
        app: fleetman-queue
    spec:
      containers:
        - name: activemq
          image: supinfo4kube/queue:1.0.1
          ports:
            - containerPort: 61616  # broker
            - containerPort: 8161   # console
---
apiVersion: v1
kind: Service
metadata:
  name: fleetman-queue
  namespace: fleetman
spec:
  selector:
    app: fleetman-queue
  ports:
    - name: broker
      port: 61616
      targetPort: 61616
    - name: console
      port: 8161
      targetPort: 8161
  type: ClusterIP
```

On le laisse en interne. Si le correcteur veut voir la console, il pourra faire un `kubectl port-forward`.

---

### 2.5 Simulateur de positions

Ce service envoie des positions dans la queue. Il doit donc pouvoir la joindre par son **nom de service Kubernetes** (`fleetman-queue`).

```yaml
# k8s/position-simulator.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fleetman-position-simulator
  namespace: fleetman
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fleetman-position-simulator
  template:
    metadata:
      labels:
        app: fleetman-position-simulator
    spec:
      containers:
        - name: simulator
          image: supinfo4kube/position-simulator:1.0.1
          env:
            - name: SPRING_PROFILES_ACTIVE
              value: "production-microservice"
          # si l'image attend des variables pour la queue, on pourrait les ajouter ici
---
apiVersion: v1
kind: Service
metadata:
  name: fleetman-position-simulator
  namespace: fleetman
spec:
  selector:
    app: fleetman-position-simulator
  ports:
    - port: 8080
      targetPort: 8080
  type: ClusterIP
```

---

### 2.6 Position tracker (API REST + Mongo)

Ce service consomme la queue et parle à Mongo. On lui donne les mêmes variables de profil.

```yaml
# k8s/position-tracker.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fleetman-position-tracker
  namespace: fleetman
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fleetman-position-tracker
  template:
    metadata:
      labels:
        app: fleetman-position-tracker
    spec:
      containers:
        - name: tracker
          image: supinfo4kube/position-tracker:1.0.1
          ports:
            - containerPort: 8080
          env:
            - name: SPRING_PROFILES_ACTIVE
              value: "production-microservice"
            # si besoin d'URL Mongo/Queue on peut les ajouter ici
---
apiVersion: v1
kind: Service
metadata:
  name: fleetman-position-tracker
  namespace: fleetman
spec:
  selector:
    app: fleetman-position-tracker
  ports:
    - port: 8080
      targetPort: 8080
  type: ClusterIP
```

---

### 2.7 API Gateway (exposé)

C’est l’entrée backend de la web app. On l’expose en NodePort 30020 parce qu’on l’a mappé dans le fichier Kind.

```yaml
# k8s/api-gateway.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fleetman-api-gateway
  namespace: fleetman
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fleetman-api-gateway
  template:
    metadata:
      labels:
        app: fleetman-api-gateway
    spec:
      containers:
        - name: api
          image: supinfo4kube/api-gateway:1.0.1
          ports:
            - containerPort: 8080
          env:
            - name: SPRING_PROFILES_ACTIVE
              value: "production-microservice"
---
apiVersion: v1
kind: Service
metadata:
  name: fleetman-api-gateway
  namespace: fleetman
spec:
  selector:
    app: fleetman-api-gateway
  type: NodePort
  ports:
    - port: 8080
      targetPort: 8080
      nodePort: 30020
```

---

### 2.8 Web App (exposée)

C’est l’interface que le correcteur doit pouvoir ouvrir dans son navigateur.

```yaml
# k8s/web-app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fleetman-web-app
  namespace: fleetman
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fleetman-web-app
  template:
    metadata:
      labels:
        app: fleetman-web-app
    spec:
      containers:
        - name: web
          image: supinfo4kube/web-app:1.0.0
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: fleetman-web-app
  namespace: fleetman
spec:
  selector:
    app: fleetman-web-app
  type: NodePort
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
```

### 2.9 API-Gateway-Alias

L’image supinfo4kube/web-app:1.0.0 a le nom du service backend en dur : fleetman-api-gateway.default.svc.cluster.local.

Comme on a tout déployé dans le namespace fleetman, le service n’existait pas dans default.

Solution : créer un service d’alias dans default vers le vrai service.

Manifeste d’alias à mettre dans le repo dans `k8s/api-gateway-alias.yaml`
```yaml
apiVersion: v1
kind: Service
metadata:
  name: fleetman-api-gateway
  namespace: default
spec:
  type: ExternalName
  externalName: fleetman-api-gateway.fleetman.svc.cluster.local
```

### 2.10 Défault-Alias

Vu ce qu’on vient de découvrir pour la web app (elle avait les noms de services en dur dans le namespace default), il y a de grandes chances que l’API Gateway et/ou le position-tracker font pareil : ils essaient de parler à fleetman-position-tracker.default.svc.cluster.local ou fleetman-mongodb.default.svc.cluster.local, mais toi tu les as mis dans fleetman
On va appliquer la même astuce que pour la web app : créer les “alias” dans le namespace default vers les vrais services dans fleetman.

'k8s/default-aliases.yaml




Avec ton `kind-config.yaml`, tu pourras alors ouvrir dans ton navigateur :

* [http://localhost:30080](http://localhost:30080) → la web app
* [http://localhost:30020](http://localhost:30020) → l’API gateway

---

### 2.9 Application des manifests

En supposant que tu as un dossier `k8s/` à côté du `kind-config.yaml` :

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/mongodb.yaml
kubectl apply -f k8s/queue.yaml
kubectl apply -f k8s/position-simulator.yaml
kubectl apply -f k8s/position-tracker.yaml
kubectl apply -f k8s/api-gateway.yaml
kubectl apply -f k8s/web-app.yaml
kubectl apply -f k8s/api-gateway-alias.yaml
kubectl apply -f k8s/default-aliases.yaml


```

Puis vérifier :

```bash
kubectl get pods -n fleetman
kubectl get svc -n fleetman
```

---

### 2.10 Petit mot sur la tolérance aux pannes

Le barème parle d’“application disponible si un worker tombe en panne”.
Là, on a mis `replicas: 1` partout pour simplifier la compréhension.
Pour gagner ces points, il suffit dans ta version finale de mettre au moins 2 réplicas sur les composants critiques (web-app, api-gateway, tracker) et de laisser Kubernetes répartir sur les workers :

```yaml
spec:
  replicas: 2
```

Comme ton cluster Kind a 1 control-plane + 2 workers, Kubernetes pourra programmer les pods sur un autre nœud si l’un tombe.

---
