---
layout: post
title: How we achieved MongoDB replication
date: 2020-03-09 23:49 +0000
---
# How we achieved MongoDB replication on Docker

## Prologue
Picture your database server. Now imagine it somehow breaks. Dispair comes up and disturbs the reaction.
Maybe you lost data. Maybe you had too much downtime. Maybe you lost work hours. Maybe you lost precious time and money.

High Availability is easily a nice-to-have but in times like these you value it more.
MongoDB comes with clustering features, which provide more storage capacity (sharding) and more reliability (replication). This article will focus on MongoDB replication on Docker containers.

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

## After


## Work done


## Conclusion
