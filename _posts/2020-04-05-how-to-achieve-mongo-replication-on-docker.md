---
layout: post
title: How to achieve Mongo replication on Docker
date: 2020-04-05 18:44 +0100
---

## Prologue

In the [previous post](https://blog.jscrambler.com/how-we-achieved-mongodb-replication-on-docker/), we showed how we used MongoDB replication to solve several problems we were facing.

Replication got to be a part of a bigger migration which brought stability, fault-tolerance, and performance to our systems. In this post, we will dive into the practical preparation of that migration.

## Motivation

I noticed the lack of tutorials of setting up Mongo replication on Docker containers and wanted to fill this gap along with some tests to see how a Mongo cluster behaves on specific scenarios.

## Objectives

To improve our production database and solve the identified limitations, our most clear objectives at this point were:

- Upgrading Mongo v3.4 and v3.6 instances to v4.2 (all community edition);
- Evolving Mongo data backup strategy from `mongodump`/`mongorestore` on a mirror server to Mongo Replication (active working backup server);
- Merging Mongo Docker containers into a single container and Mongo Docker volumes into a single volume.

## Step-by-step

### 1. Prepare applications for Mongo connection string change

When our applications were developed, there was no need to pass the Mongo connection URI through a variable, as most of the time Mongo was deployed as a microservice in the same stack as the application containers. With the centralization of Mongo databases, this change was introduced in the application code to update the variable on our CI/CD software whenever we need.

### 2. Generate and deploy keyfiles

[MongoDB’s official documentation](https://docs.mongodb.com/manual/tutorial/enforce-keyfile-access-control-in-existing-replica-set/) has step-by-step instructions on how to setup Keyfile authentication on a Mongo Cluster. Using keyfile authentication enforces [Transport Encryption](https://docs.mongodb.com/manual/core/security-transport-encryption/) over SSL.

```bash
openssl rand -base64 756 > <path-to-keyfile>
chmod 400 <path-to-keyfile>
```

The keyfile is passed through a `keyfile` argument on the `mongod` command, as shown in the next step.

[User authentication](https://docs.mongodb.com/manual/tutorial/enable-authentication) and role management is out of the scope of this post, but if you are going to use it, configure it before proceeding beyond this step.

### 3. Deploy existing containers with the `replSet` argument

```bash
mongod --keyfile /keyfile --replSet=rs-myapp
```

### 4. Define ports

Typically, in this step, you simply choose a server network port to serve your MongoDB. Mongo’s default port is 27017, but since in our case we had 4 apps in our production environment, we defined 4 host ports. You should always choose a network port per Mongo Docker container and stick with them.

- 27001 for app 1
- 27002 for app 2
- 27003 for app 3
- 27004 for app 4

At step 12, after having replication working, we'll only use and expose one port.

### 5. Assemble a cluster composed of 3 servers in different datacenters and regions

Preferably, set up 3 servers on different datacenters, or different regions if possible. This will allow for inter-regional availability. Aside from latency changes, your system will survive datacenter blackouts and disasters.

Why 3? It is the minimum number for a worthy Mongo cluster.

- 1 node: can't have high availability by itself;
- 2 nodes: no automatic failover - when one of them fails, the other one can't elect itself as primary alone;
- 3 nodes: minimum worth number - when one of them fails, the other two vote for the next primary node;
- 4 nodes: has the same benefits as 3 nodes plus one extra copy of data (pricier);
- 5 nodes: can withstand 2 nodes failure at the same time (even pricier).

There are Mongo clusters with [arbiters](https://docs.mongodb.com/manual/core/replica-set-arbiter/), but that is out of the scope of this post.

### 6. Define your replica set members’ priorities

Adjust your priorities to your cluster size, hardware, location, or other useful criteria.

In our case, we went for:
```js
appserver: 10 // temporarily primary
node1: 3 // designated primary
node2: 2 // designated first secondary being promoted
node3: 1 // designated second secondary being promoted
```

We set the node which currently had the data with `priority: 10`, since it had to be the primary in the sync phase, while the rest of the cluster is not ready. This allowed continuing serving database queries while data was being replicated.

### 7. Deploy Mongo containers scaling to N* on a Mongo cluster

(\*N being the number of Mongo cluster nodes).

Use an orchestrator to deploy 4 Mongo containers in the environment, scaling to 3.

- 4 is the number of different Mongo instances;
- 3 is the number of Mongo cluster nodes.

In our case, this meant having 12 containers in the environment temporarily.

![environment-middlestep](https://res.cloudinary.com/practicaldev/image/fetch/s--R-MP1A78--/c_limit%2Cf_auto%2Cfl_progressive%2Cq_auto%2Cw_880/https://blog.jscrambler.com/content/images/2020/05/jscrambler-blog-how-to-achieve-mongodb-replication-docker-env.png)

Remember to deploy them as replica set members, as shown in step 3.

### 8. Replication time!

This is the moment when we start watching database users and collection data getting synced. You can enter the `mongo` shell of a Mongo container (preferably primary) to check the replication progress. These two commands will show you the status, priority and other useful info:
```bash
rs.status()
# and
rs.conf()
```

When all members reach the secondary state, you can start testing. Stop the primary node to witness secondary promotion. This process is almost instantaneous.

You can stop the primary member by issuing the following command:

```bash
docker stop <mongo_docker_container_name_or_d>
```

When you bring it back online, the cluster will give back the primary role to the member with the highest `priority`. This process takes a few seconds, as it is not critical.

```bash
docker start <mongo_docker_container_name_or_id>
```

### 9. Extract Mongo containers from application servers

If everything is working at this point, you can stop the Mongo instance on which we previously set `priority: 10` (stop command in the prior step) and [remove that member from the replica set passing its hostname as parameter](https://docs.mongodb.com/manual/reference/method/rs.remove/).

Repeat this step for every Mongo container you had on step 4.

### 10. Migrate backups and change which server they read the data from

As mentioned in the [previous post](https://blog.jscrambler.com/how-we-achieved-mongodb-replication-on-docker/), one handy feature of MongoDB replication is having a secondary member asking for data to `mongodump` from another secondary member.

Previously, we had the application + database server performing `mongodump` of its data. As we moved the data to the cluster, we also moved the automated backup tools to a secondary member, to take advantage of said feature.

### 11. Merge data from 4 Mongo Docker containers into one database

**If you only had 1 Mongo Docker container at the start, skip to step 13.**

Besides having simplicity telling us to do this **before** step 1, we decided to act cautiously and keep apps and databases working in a way as close as they were before until we mastered Mongo replication in our environment.

At this stage, we chose to import data from all Mongo databases to a single Mongo database - the one which contained the most data. When working with MongoDB, remember this line from the [official docs](https://docs.mongodb.com/manual/core/databases-and-collections/):

> In MongoDB, databases hold collections of documents.

That means we can take advantage of `mongodump --db <dbname>` and `mongorestore --db <dbname>` to merge Mongo data into the same instance (this goes for non-Docker as well).

### 12. Monitor cluster nodes and backups

When you have merged your databases into the same instance, you will shut down other instances, right? Then, you will only need to monitor the application and perform backups of that same instance. Don't forget to monitor the new cluster hardware. Even with automatic fault-tolerance, it is not recommended to leave our systems short. As a hint, there is a [dedicated role for that](https://docs.mongodb.com/manual/reference/built-in-roles/#clusterMonitor) called `clusterMonitor`.

## Conclusion

Sharing this story about our database migration will hopefully help the community - especially those not taking full benefits from MongoDB already - to start seeing MongoDB in a more mature and reliable way.

Even though this is not a regular MongoDB replication "how-to" tutorial, this story shows important details about MongoDB’s internal features, our struggle to not leave any details behind, and, again, the benefits of such technology. That's what I believe technology is for - helping humans with their needs.
