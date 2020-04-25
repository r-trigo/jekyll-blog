---
layout: post
title: How to achieve Mongo replication on Docker
date: 2020-04-05 18:44 +0100
---

# How to achieve Mongo replication on Docker
## Prologue
In the [previous post](2020-03-09-how-we-achieved-mongodb-replication.md), we showed how we used MongoDB replication to solve several problems we were facing before adopting it. Replication got to be a part of a bigger migration which brought stability, fault-tolerance and performance to our systems. In this post we will dive into the practical preparation of that migration.


## Motivation (para além da mesma do post anterior)
I noticed the lack of tutorials of setting up Mongo replication on Docker containers and wanted to fill this gap along with some tests to see how a Mongo cluster behaves on specific scenarios.


## :checkered_flag: Objectives (Igual ao post anterior)
>To improve our production database and solve the identified limitations, our most clear objectives at this point were:
>- Upgrading Mongo v3.4 and v3.6 instances to v4.2 (all community edition)
>- Changing Mongo data backup strategy from **mongodump/mongorestore** to Mongo Replication
>- Merging Mongo containers into a single container and Mongo Docker volumes into a single volume

## Procedure steps (não soa muito bem :smile:)
1. prepare applications for Mongo connection string change

Needs change over time. When our applications were developed, there was no need to pass the Mongo connection URI through a variable, as most of the times Mongo was deployed as a microservice in the same stack as the application containers. With the centralization of Mongo databases, this change was introduced in the application code to update the variable on our CI/CD software whenever we need.

2. generate and deploy keyfiles

[MongoDB official documentation](https://docs.mongodb.com/manual/tutorial/enforce-keyfile-access-control-in-existing-replica-set/) has step-by-step instructions on how to setup Keyfile authentication on a Mongo Cluster. Using keyfile authentication enforces [Transport Encryption](https://docs.mongodb.com/manual/core/security-transport-encryption/) over SSL.

```bash
openssl rand -base64 756 > <path-to-keyfile>
chmod 400 <path-to-keyfile>
```

The keyfile is passed through *keyfile* argument on **mongod** command, as shown in the next step.

3. deploy existing containers with *replSet* argument

```bash
mongod --keyfile /keyfile --replSet=rs-myapp
```

4. define ports

Simply choose a server network port to serve your Mongo DB. 27017 is Mongo default port, but since in our case we had 4 apps in our production environment, we defined host ports. Choose a network port per Mongo Docker container and stick with them.
- 27001 for app 1
- 27002 for app 2
- 27003 for app 3
- 27004 for app 4

**(insert step number)**

After having replication working, when we reach Mongo container merge step, we only use and expose one.

5. assemble a cluster composed of 3 servers in different datacenters and regions

Preferably, setup 3 servers on different datacenters, or different regions if possible. This will allow inter-regional availability. Aside from latency changes, your system will survive datacenter blackouts and disasters.

Why 3? It is the minimum number for a worthy Mongo cluster.

1 node: can't have high availability by itself
2 nodes: no automatic failover - when one of them fails, the other one can't elige itself as primary alone
3 nodes: minumum worth number - when one of them fails, the other two vote the next primary node
4 nodes: same benefits as 3 nodes plus one extra copy of data, but pricier
5 nodes: can whitstand 2 nodes failure at the same time, but even pricier

There are Mongo clusters with [arbiters](https://docs.mongodb.com/manual/core/replica-set-arbiter/), but that is out of the scope of this post.

6. Define your replica set members priorities
Adjust your priorities to your cluster size, hardware, location or other useful criteria.

In our case, we went for:
```js
appserver: 10 // temporarily primary
node1: 3 // designated primary
node2: 2 // designated first secondary being promoted
node3: 1 // designated second secondary being promoted
```

We set the node who currently had the data with priority **10**, since it had to be the primary in the sync phase, while the rest of the cluster is not ready. This allowed to continue serving database queries while data was being replicated.

7. deploy Mongo containers scaling to N on a Mongo cluster
(being N the number of Mongo cluster nodes)

Use an orchestrator to deploy 4 mongo containers, scaling to 3, having 4 on each host.
4 is the number of Mongo containers
3 is the number of Mongo cluster nodes
In our case this meant having 12 containers temporarily.

TODO: Diagram

Remember to deploy them as replica set members, as shown in step 3.

8. Replication time!
This is the moment when we start watching database users and collection data getting synced. You can enter the mongo shell of a Mongo container (preferably primary) to check replication progress. These two commands will show you the status, priority and other useful info:
```bash
rs.status()
# and
rs.conf()
```  

9. extract 3 Mongo containers from main application server
When all members reach secondary state, you can start testing stopping the primary node to witness secondary promotion. This process is almost instantaneous.

You can stop primary by issuing the following command:
```bash
docker stop <mongo_docker_container_name_or_d>
```

When you bring it back, the cluster will give back primary status to the member with most priority. This part takes a few seconds, as it is not critical.

```bash
docker start <mongo_docker_container_name_or_d>
```

10. extract another Mongo docker container from a minor application server
11. migrate backups and change which server they read the data
12. merge data from 4 Mongo docker containers into one database
13. unify backups
