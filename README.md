# base_infrastructure

Infrastructure for base server

#### For postgreSQL multiple databases scripts:

```sh
chmod +x scripts/create-multiple-postgresql-databases.sh
```

#### For [pgAdmin](https://www.pgadmin.org/docs/pgadmin4/latest/container_deployment.html#mapped-files-and-directories):

```sh
sudo chown -R 5050:5050 <host_directory>
```

#### Database backup & restore:

Backup:

```sh
docker exec -t <postgres-container-id> pg_dumpall -c -U <user> > dump_`date +%d-%m-%Y"_"%H_%M_%S`.sql
```

Restore:

```sh
cat <dump_name>.sql | docker exec -i <postgres-container-id> psql -U <user>
```

#### Example of connection:

```sh
# host = container_name
postgres://username:password@container_name:port/db_name
```
