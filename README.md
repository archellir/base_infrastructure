# base_infrastructure

Infrastructure for base server

First step:

1. Start Caddy & Portainer with with `docker_compose.yml` in `/caddy`
2. Start other services using `docker_compose.yml` 1 by 1


#### TO BE DEPRECATED: PORTAINER COOMUNITY EDITION REMOVED FUNCTIONALITY

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
