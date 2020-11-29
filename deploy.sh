#!/bin/bash

### ENV ###
DOMAIN="$CI_COMMIT_REF_SLUG".tech.domain.ru
ROOT_PATH="/mnt/u01/ext_www/$DOMAIN"
DB_NAME="$CI_COMMIT_REF_SLUG"_db
DB_USER="$CI_COMMIT_REF_SLUG"_user
DB_PASS=`date +%s | sha256sum | base64 | head -c 16`

# COLORS
red='\e[1;31m%s\e[0m\n'
green='\e[1;32m%s\e[0m\n'
yellow='\e[1;33m%s\e[0m\n'

function SiteCreate () {
### Create new site, if does not exists yet
if [ ! -d "$ROOT_PATH" ]; then
        /opt/webdir/bin/bx-sites -v -a create -s "$DOMAIN" -d "$DB_NAME" -t kernel -u "$DB_USER" -p "$DB_PASS" -r "$ROOT_PATH"
        printf "\nCI_COMMIT_REF_SLUG: $CI_COMMIT_REF_SLUG"
        printf "\nDOMAIN: $DOMAIN"
        printf "\nROOT_PATH: $ROOT_PATH"
        printf "\nDB_NAME: $DB_NAME"
        printf "\nDB_USER: $DB_USER"
else
        printf "\n$yellow" "Site $DOMAIN is already exists, getting the new code from $CI_COMMIT_REF_NAME..."
        printf "Getting changes from gitlab..."
        SyncGit
        exit 0
fi
}

function SiteCheck {
### Checking site status
## Checking status of first created emtpy site
if [ $1 = "tmpl" ]; then
        /opt/webdir/bin/bx-sites -a status -s "$DOMAIN" | grep status | grep "not_installed"

while [ $? -ne 0 ]; do
        printf .
        /opt/webdir/bin/bx-sites -a status -s "$DOMAIN" | grep status | grep "not_installed" >/dev/null
done

printf "\n$green" "New empty site "$DOMAIN" successfully created"
fi

## Checking status full site after all sync (files & DB) from stage
if [ $1 = "full" ]; then
        /opt/webdir/bin/bx-sites -a status -s "$DOMAIN" | grep status | grep "finished" >/dev/null

while [ $? -ne 0 ]; do
        printf .
        /opt/webdir/bin/bx-sites -a status -s "$DOMAIN" | grep status | grep "finished" >/dev/null
done

printf "\n$green" "Site "$DOMAIN" successfully created"
fi

## Checking status after delete
if [ $1 = "delete" ]; then
        /opt/webdir/bin/bx-sites -a status -s "$DOMAIN" | grep status | grep "finished" >/dev/null

while [ $? -ne 1 ]; do
        printf .
        /opt/webdir/bin/bx-sites -a status -s "$DOMAIN" | grep status | grep "finished" >/dev/null
done
sleep 7
printf "\n$green" "Env for "$DOMAIN" successfully removed"
fi
}

function SyncFiles {
### Sync files from stage to local
echo "Sync files from the stage to the local disk..."
rsync --rsync-path='sudo rsync' -av --delete --exclude='/.git' --exclude='/bitrix/cache' --exclude='/bitrix/managed_cache' bx-ci-files@ETALON_IP:/mnt/u01/ext_www/ETALON/ /mnt/u01/bx_stage_files >/root/rsync_from_stage && printf "$green" "Sync is OK"

### Sync from local to new site
echo "Sync files from local to $ROOT_PATH ..."
rsync -av --delete --exclude='/bitrix/php_interface/dbconn.php' --exclude='/bitrix/php_interface/dbconn.php' --exclude='/bitrix/.settings.php' /mnt/u01/bx_stage_files/ $ROOT_PATH >/root/rsync_to_new_site && printf "$green" "Sync is OK"
rm -f $ROOT_PATH/bitrix/.setting_extra.php
}

function SyncGit {
### Get changes from fit
printf "Getting changes from gitlab..."
cd $ROOT_PATH
sudo -u bitrix git ls-files --others --exclude-standard -z |
while IFS= read -r -d '' file;
  do sudo -u bitrix git clean -f $file;
done

sudo -u bitrix git clean -f info/
sudo -u bitrix git fetch && printf "$green" "git fetch ok"
sudo -u bitrix git reset --hard && printf "$green" "git reset ok"
sudo -u bitrix git checkout -b $CI_MERGE_REQUEST_SOURCE_BRANCH_NAME origin/$CI_MERGE_REQUEST_SOURCE_BRANCH_NAME && printf "$green" "Current branch is: $CI_MERGE_REQUEST_SOURCE_BRANCH_NAME"
}

function SyncDB {
### Sync DB from stage to new site
echo "Copying DB from the stage..."
mysqldump -h localhost --single-transaction --set-gtid-purged=OFF ETALON_DB | mysql "$CI_COMMIT_REF_SLUG"_db && printf "$green" "Copying is successful"
}

function SiteDelete {
/opt/webdir/bin/bx-sites -a delete -s $DOMAIN
rm -f /var/log/nginx/"$CI_COMMIT_REF_SLUG"_{access,error}.log
rm -f /var/log/httpd/"$CI_COMMIT_REF_SLUG"_{access,error}_log
}

### Functions to call from gitlab runner
if [ $1 = "create" ]; then
        echo "Deploying the env for $CI_COMMIT_REF_SLUG (argument is \"$1\")"
        SiteCreate
        SiteCheck tmpl
        SyncFiles
        SyncGit
        SyncDB
        SiteCheck full
elif [ $1 = "delete" ]; then
        echo "Removing the env for $CI_COMMIT_REF_SLUG (argument is \"$1\")"
        SiteDelete
        SiteCheck delete
else
        echo "Run script with argument "create" of "remove""
fi
