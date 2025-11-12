# Barème de Notation (40 points)

| Critère | Points |
|---------|--------|
| Un déploiement et un service existent pour trucks-position-simulator | 2 |
| Un déploiement et un service existent pour trucks-queue | 2 |
| Un déploiement et un service existent pour trucks-position-tracker | 2 |
| Un déploiement et un service existent pour trucks-api-gateway | 2 |
| Un déploiement et un service existent pour trucks-web-app | 2 |
| La base de données MongoDB est présente et persistée | 7 |
| Les composants du projet sont isolés de manière appropriés | 3 |
| Un document prouve qu'un cluster Kubernetes a été monté | 13 |
| Les instructions fournies sont claires et concises | 3 |
| L'application reste disponible si l'un des deux nœuds worker est en échec | 4 |
| **TOTAL** | **40** |

## Détails des critères

### Déploiements et Services (10 points)
Chacun des 5 composants doit avoir :
- Un déploiement Kubernetes configuré
- Un service pour exposer le composant

### Persistance des données (7 points)
- MongoDB doit être déployé
- Les données doivent être persistées avec un PersistentVolume

### Architecture (3 points)
- Isolement approprié des composants via namespaces ou labels

### Documentation (13 points)
- Preuve documentée du cluster Kubernetes monté
- Procédure d'installation clairement décrite

### Instructions (3 points)
- Documentation claire et facile à suivre

### Résilience (4 points)
- L'application doit rester opérationnelle avec un nœud worker défaillant
- Réplication appropriée des pods