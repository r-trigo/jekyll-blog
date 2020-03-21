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
- Upgrade Mongo v3.4 and v3.6 instances to v4.2

## Before
TODO: diagram

**Production servers**
- server_1: application services containers + 2 mongo containers
- server_2: application services containers + 1 mongo containers
- server_3: application services containers + 1 mongo containers

**Mirror servers**
- mirror_server_1: application services containers + 2 mongo containers (updated once a day)
- mirror_server_2: application services containers + 1 mongo containers (updated once a day)
- (services and data on server3 were not in mirror environment)

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

**WARNING**: The process of mongorestore utility is NOT incremental. Restoring a database will recreate all data.

```bash
mongorestore --host=mongodb1.example.net --port=3017 --username=user  --authenticationDatabase=admin /opt/backup/mongodump-2013-10-24
```

### Problems and limitations found

1. **Late backup data**:
Since mongodump ran daily during dawn, the data from that time until the moment of the database switch would be lost.
2. **Unavailability**:
mongodump and mongorestore in biggest databases took several hours. During the restore of the DB, nothing could be done as it can't be used util mongorestore is finished. Only when completed the DB will be available. Also, switching from production environment to mirror environment was a manual process which took some time.
3. **Disk usage**:
Restoring a whole database (or several DBs simultaneously) will take up disks inodes, as well as taking a toll of usage in your disks.
4. **Scalability**:
Using a Mongo Docker instance for each database, even distributed by different servers, brought the need of setting up an instance, different network addresses and ports and new backup containers (mongo-tools). A Mongo cluster would fit the needs for our applications and make database administration way simpler.  
5. **Reserved memory**:
By default, each Mongo container will try to cache all available memory until 60%. Since we previously had 1 Mongo container on two application servers and 2 containers in the same application server, all of them had at least 60% busy (in use + cached). Whenever there is more than one Mongo container, they will dispute all available memory to reach 60% each. (2 -> 120%, 3 -> 180%, 4 -> 240%, etc.). For these reasons, it is for very important to set adequate container memory limits.
6. **Amount of Docker volumes**:
MongoDB data, dumps and metadata were scattered through several Docker volumes, mapped to different filesystem folders. Merging these databases would allow to centralize this data.
7. **Security and features**:
Upgrading to Mongo 4 would solve security issues and bring more features to improve DB performance and replication (fontes? listar features?)


## After
1. **Fault-tolerance**:
Automatic and instant primary database switch.
2. **Data redundancy**:
Instantaneously synced redundant data.
3. **Inter-regional availability**:
Location disaster safeguarding.
4. **Cluster hierarchy**:
Mongo replication allows nodes priority configuration, which allows the user to order nodes by hardware power, location, or other useful criteria.
5. **Read operations balance**
Read operations can be balanced through secondary nodes, like dashboards queries and mongodumps.
Applicationss can also be configured (through Mongo connection URI) to perform read operations from secondary nodes, which increases database read capacity.
6. **Performance**
Now that memory used and cached is right for the system needs, Mongo databases are hosted in dedicated servers, version got bumped and cluster can balance read operations, performance improvements exceeded the expectations.


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
- Data corruption gets synced


## Conclusion
TODO: Hardware chart screenshots?
The whole process was done with intervals between major steps, since we wanted to check if the new strategy was working for us. We are very glad to have all the problems in the **before** section solved. There were a lot of reasons to do all of this and we are now prepared to scale easily and sleep well knowing that MongoDB has (at least) database fault-tolerance and recovers by itself instantaneously.
