---
layout: post
title: How we achieved MongoDB replication
date: 2020-03-09 23:49 +0000
---
# :leaves: :sheep: :whale: How we achieved MongoDB replication on Docker

## Prologue
Picture your database server. Now imagine it somehow breaks. Dispair comes up and disturbs the reaction.
Maybe you lost data. Maybe you had too much downtime. Maybe you lost work hours. Maybe you lost precious time and money.

High Availability is easily a nice-to-have but in times like these you value it more.
MongoDB comes with clustering features, which provide more storage capacity (sharding) and more reliability (replication). This article will focus on MongoDB replication on Docker containers.

## :checkered_flag: Objectives
- Change Mongo data backup strategy from **mongodump/mongorestore** to Mongo Replication
- Upgrade Mongo v3.4 and v3.6 to v4.2

## Before
TODO: diagram

**Production server**
- application services containers
- 3 mongo services containers

**Hot backup server**
- application services containers
- 3 mongo services containers (updated once a day)

The mongo service was kept using a mongodump/mongorestore strategy.

### mongodump/mongorestore strategy

The first part of mongodump/mongorestore strategy is composed of cronjobs which dump the data in the Mongo database to a different mongo instance with mongodump utility.

###### mongodump
> mongodump is a utility for creating a binary export of the contents of a database. mongodump can export data from either mongod or mongos instances; i.e. can export data from standalone, replica set, and sharded cluster deployments.

```bash
mongodump --host=mongodb1.example.net --port=3017 --username=user --password="pass" --out=/opt/backup/mongodump-2013-10-24
```

The second part of this strategy is restoring the second database by the data in the mongodump with mongorestore utility.

###### mongorestore
> The mongorestore program loads data from either a binary database dump created by mongodump or the standard input (starting in version 3.0.0) into a mongod or mongos instance.

**WARNING**: This process is NOT incremental. Restoring a database will recreate all data.

```bash
mongorestore --host=mongodb1.example.net --port=3017 --username=user  --authenticationDatabase=admin /opt/backup/mongodump-2013-10-24
```

### Problems and limitations found
1. Machine failure
  - Late data
    - since mongodump ran daily during dawn, the data from that time would be lost
  - Unavailability, mongorestore process time
    - mongodump and mongorestore in biggest databases took several hours
2. Horizontal escalation not possible
3. MongoDB starves for RAM
  - by default, each Mongo container will try to cache all available memory until 60%
  - since we previously had 1 container on two application servers and 2 containers in the same application server, all of them had at least 60% busy (in use + cached)
  - whenever there is more than one Mongo container, they will fight for all the available memory trying to reach 60% each (2 -> 120%, 3 -> 180%, 4 -> 240%, etc.)
  - it is very important to set container memory limits
4. Mongodumps and Mongorestores were scheduled to run at the same time, causing inode usage alerts
5. Mongo version 3 lacked Mongo version 4 features
6. Centralize Docker volumes


## After (filter me)
1. Service fault-tolerance
  - Automatic and instant writing database switch
  - provides redundancy
  - increases data availability
2. Inter-regional cluster
3. Cluster hierarchy
4. Data redundancy (instantaneously synced)
5. Better server performance
6. Read operations can be balanced through secondary nodes
  - Dashboard queries and mongodumps
  - increased read capacity (clients can send read operations to different servers)


## Work done
- extracted 3 Mongo docker containers from main application server
- extracted another Mongo docker container from a minor application server
- assembled a cluster composed of 3 servers in different datacenters and regions
- planted 4 Mongo containers scaling to 3 on a Mongo cluster
- merged data from 4 Mongo docker containers into one database
- migrated backups and change which server they read the data
- unified backups
- generated and deploy keyfiles
- prepared applications for mongo connection string change
- define ports
- deploy existing containers with replSet argument


### :v: Final state
- **Staging** application server should point back to its Mongo instances, without **mongodump**
- **Production** application servers should point to Mongo Production Cluster using replica set
- **Mirror** application server should point to to its Mongo instances and keep storing most recent **mongodumps**
- **Mongo Cluster** secondary node should **mongodump** the cluster data to Mirror environment, asking for it to another secondary node


## Strategy uncovered problems
- On a 3 node cluster, when 2 nodes are offline, the last one enters state "RECOVERING". To keep the service running, enter this instance and remove the remaining nodes from the replica set. There is an an interactive script for this called Mongo Lonely Replica.


## Conclusion
TODO: Hardware chart screenshots?
The whole process was done with intervals between major steps, since we wanted to trust the new strategy was working for us. We are very glad to have all the problems in the **after** section solved. There were a lot of reasons to do all of this and we are now prepared to scale easily and sleep well knowing that MongoDB has (at least) database fault-tolerance and recovers by itself instantaneously.
