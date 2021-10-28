#!/usr/bin/env bash

WORKDIR=/apps
DATA_DIR=$WORKDIR/data
UPDATE_DIR=$DATA_DIR/update
DOWNLOAD_DIR=$DATA_DIR/download

set_taginfo_config() {
    echo "Setting up $WORKDIR/taginfo-config.json file ..."

    # Update dir values in taginfo-config.json
    grep -v '^ *//' $WORKDIR/taginfo/taginfo-config-example.json |
        jq '.logging.directory                   = "'$UPDATE_DIR'/log"' |
        jq '.paths.download_dir                  = "'$UPDATE_DIR'/download"' |
        jq '.paths.bin_dir                       = "'$WORKDIR'/taginfo-tools/build/src"' |
        jq '.sources.db.planetfile               = "'$UPDATE_DIR'/planet/planet.osm.pbf"' |
        jq '.sources.chronology.osm_history_file = "'$UPDATE_DIR'/planet/history-planet.osh.pbf"' |
        jq '.sources.db.bindir                   = "'$UPDATE_DIR'/build/src"' |
        jq '.paths.data_dir                      = "'$DATA_DIR'"' \
            >$WORKDIR/taginfo-config.json

    # Update instance values in taginfo-config.json
    [[ ! -z ${INSTANCE_URL+z} ]] && jq --arg a "${INSTANCE_URL}" '.instance.url = $a' $WORKDIR/taginfo-config.json >tmp.json && mv tmp.json $WORKDIR/taginfo-config.json
    [[ ! -z $INSTANCE_NAME+z} ]] && jq --arg a "${INSTANCE_NAME}" '.instance.name = $a' $WORKDIR/taginfo-config.json >tmp.json && mv tmp.json $WORKDIR/taginfo-config.json
    [[ ! -z $INSTANCE_DESCRIPTION+z} ]] && jq --arg a "${INSTANCE_DESCRIPTION}" '.instance.description = $a' $WORKDIR/taginfo-config.json >tmp.json && mv tmp.json $WORKDIR/taginfo-config.json
    [[ ! -z $INSTANCE_ICON+z} ]] && jq --arg a "${INSTANCE_ICON}" '.instance.icon = $a' $WORKDIR/taginfo-config.json >tmp.json && mv tmp.json $WORKDIR/taginfo-config.json
    [[ ! -z $INSTANCE_CONTACT+z} ]] && jq --arg a "${INSTANCE_CONTACT}" '.instance.contact = $a' $WORKDIR/taginfo-config.json >tmp.json && mv tmp.json $WORKDIR/taginfo-config.json

    # languages wiki databases will be downloaded from OSM
    jq --arg a "languages wiki" '.sources.download = $a' $WORKDIR/taginfo-config.json >tmp.json && mv tmp.json $WORKDIR/taginfo-config.json
}

updates_create_db() {
    local CREATE_DB="$1"
    [[ ! -z $CREATE_DB+z} ]] && jq --arg a "${CREATE_DB}" '.sources.create = $a' $WORKDIR/taginfo-config.json >tmp.json && mv tmp.json $WORKDIR/taginfo-config.json
}

updates_source_code() {
    echo "Updating source code, in order to make the code running..."

    # Function to replace the projects repo to get the projects information
    TAGINFO_PROJECT_REPO=${TAGINFO_PROJECT_REPO//\//\\/}
    sed -i -e 's/https:\/\/github.com\/taginfo\/taginfo-projects.git/'$TAGINFO_PROJECT_REPO'/g' $WORKDIR/taginfo/sources/projects/update.sh

    # The follow line is requiered to avoid sqlite3 issues
    sed -i -e 's/run_ruby "$SRCDIR\/update_characters.rb"/ruby "$SRCDIR\/update_characters.rb"/g' $WORKDIR/taginfo/sources/db/update.sh
    sed -i -e 's/run_ruby "$SRCDIR\/import.rb"/ruby "$SRCDIR\/import.rb"/g' $WORKDIR/taginfo/sources/projects/update.sh
    sed -i -e 's/run_ruby "$SRCDIR\/parse.rb"/ruby "$SRCDIR\/parse.rb"/g' $WORKDIR/taginfo/sources/projects/update.sh
    sed -i -e 's/run_ruby "$SRCDIR\/get_icons.rb"/ruby "$SRCDIR\/get_icons.rb"/g' $WORKDIR/taginfo/sources/projects/update.sh
}

download_planet_files() {
    mkdir -p $UPDATE_DIR/planet/

    # Check if URL_PLANET_FILE_STATE exist and set URL_PLANET_FILE
    if [[ ${URL_PLANET_FILE_STATE} && ${URL_PLANET_FILE_STATE-x} ]]; then
        URL_PLANET_FILE=$(curl -D -X GET $URL_PLANET_FILE_STATE)
    fi

    # Check if URL_HISTORY_PLANET_FILE_STATE exist and set URL_HISTORY_PLANET_FILE
    if [[ ${URL_HISTORY_PLANET_FILE_STATE} && ${URL_HISTORY_PLANET_FILE_STATE-x} ]]; then
        URL_HISTORY_PLANET_FILE=$(curl -D -X GET $URL_HISTORY_PLANET_FILE_STATE)
    fi
    # Download pbf files
    wget --no-check-certificate -O $UPDATE_DIR/planet/planet.osm.pbf $URL_PLANET_FILE
    wget --no-check-certificate -O $UPDATE_DIR/planet/history-planet.osh.pbf $URL_HISTORY_PLANET_FILE

}

update() {
    echo "Update Sqlite DBs at $(date +%Y-%m-%d:%H-%M)..."

    # Download OSM planet replication and full-history files,
    download_planet_files

    # In order to make it work we need to pass first one by one the creation and then all of them "db projects chronology"
    for value in $CREATE_DB; do
        updates_create_db $value
        $WORKDIR/taginfo/sources/update_all.sh $UPDATE_DIR
    done

    updates_create_db $CREATE_DB
    $WORKDIR/taginfo/sources/update_all.sh $UPDATE_DIR

    # Copy db files into data folder
    cp $UPDATE_DIR/*/taginfo-*.db $DATA_DIR/
    cp $UPDATE_DIR/taginfo-*.db $DATA_DIR/

    # Link to download db zip files
    chmod a=r $UPDATE_DIR/download
    ln -sf $UPDATE_DIR/download $WORKDIR/taginfo/web/public/download
}

start_web() {
    echo "Start taginfo..."
    cd $WORKDIR/taginfo/web && bundle exec rackup --host 0.0.0.0 -p 4567
}

continuous_update() {
    while true; do
        update
        sleep $TIME_UPDATE_INTERVAL
    done
}

main() {
    set_taginfo_config
    updates_source_code

    # Check if db files are store in the $DATA_DIR in order to start the service or start procesing the file
    NUM_DB_FILES=$(ls $DATA_DIR/*.db | wc -l)
    if [ $NUM_DB_FILES -lt 7 ]; then
        update
    fi
    start_web &
    continuous_update
}

main
