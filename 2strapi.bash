#!/bin/bash
#250131 2strapi.bash 26/01/25
# Import a table from an origin postgresql db into a table in a strapi project
#	Create destination table relevant to  Strapi table structure
#	Create Stapi model
## Usage : ./2strapi.bash <model> (model=table name without final s)

## Completeness
#  not all data types managed
#  function 2strapi_type must be completed

## A useful but dangerous command
# rm -fR  dist/src/api/<table>/: rm src/api/<table>; psql bons -c "DROP TABLE <tables>"
# delete all from this collection '<table>', to be used if you want to relaunch the script on the same table

## prerequisites
# CREATE EXTENSION dblink;				-- with postgres user
# ALTER USER <user> WITH superuser;			-- with postgres user (see postgresql/dblink doc tu review other solutions)

## Origin & Destination projects parameters
PG_USER="philippe"
PG_DB1="bons"				# Destination (Strapi) DB
PG_DB2="bon9"				# Origin DB
PG_HOST1="localhost"		# DB1 host
PG_HOST2="localhost"		# DB2 host
DIR1=/var/www/html/Bons		# Strapi project 

## Other parameters
SEP=';'									# Fields SEParator
SEP2='_'								# blanc -> SEP2 in type (read reads words)
ATT="timestamp(6) without time zone"	# created_at, ... format

## Options
PUBLISH=false			# True to add "published Strapi fonctionnality"
VERBOSE=false			# True to print internal variables

model_name=$1
if [[ -z "$model_name" ]]; then
	echo "Usage : ./2strapi.bash <model> (model=table_name without final s)"
	exit
fi
table=$model_name"s"
displayed_name=${model_name^}

# Functions (most of the fucntions setup some variables that are used to create the table & model)
#--------------------------------------------------------------------------------------------------------#
function check_i(){
	# Check if table exists in destination db
	psql -U $PG_USER -d $PG_DB1 -t -c "SELECT to_regclass('$table');" | grep -q "$table"
	if [ $? -eq 0 ]; then
 	 	echo "Table $table exists in destination DB."
		exit 1
	fi
	# Check if model exists in destination project
	if [[ -f "$DIR1/src/api/$table" ]]; then
 	 	echo "Model (src/api/$table) exists in destination project."
		exit 1
	fi
} # End check_i
#--------------------------------------------------------------------------------------------------------#
function columns_o() {
	# columns & types of original table -> destination 0
	columns_and_types=$(psql -U "$PG_USER" -d "$PG_DB2" -h "$PG_HOST2" -t -c "
SELECT 
    column_name || '$SEP' || data_type || 
    CASE
        WHEN data_type = 'character varying' THEN 
            '(' || character_maximum_length || ')'
        WHEN data_type = 'character' THEN 
            '(' || character_maximum_length || ')'
        WHEN data_type = 'numeric' THEN
            '(' || numeric_precision || ',' || numeric_scale || ')'
        ELSE ''
    END AS column_definition
FROM information_schema.columns 
WHERE table_name = '$table' 
AND table_schema = 'public';
")
	# columns_o=$(echo "$columns_and_types" | awk '{print $1}' | tr '\n' $SEP | sed 's/,$//')			#Ok avec l'ancien SEP=' '
	# column_types_o=$(echo "$columns_and_types" | awk '{print $2}' | tr '\n' $SEP | sed 's/,$//')			#KO car peut exister des blancs dans les type
	IFS=$'\n' read -d EOF -r -a column_array <<< "$columns_and_types"
	columns_o=''
	column_types_o=''
	for e in "${column_array[@]}"; do
		IFS=';' read -r column_name column_type <<< "$e"
		column_name="${column_name#" "}"				# Supprime le 1er blanc
		column_type="${column_type#" "}"				# Supprime le 1er blanc
		if [[ -z "$columns_o" ]]; then
			columns_o="$column_name"
			column_types_o="$column_type"
		else
			columns_o="$columns_o$SEP$column_name"
			column_types_o="$column_types_o$SEP$column_type"
		fi
	done
	columns_d=$columns_o
	column_types_d=$column_types_o	
} # End columns_o
#--------------------------------------------------------------------------------------------------------#
function column_delete() {
	# Delete a column from columns_d & column_types_d
	# Used to reorder column as "Strapi standard"
	column=$1

	IFS=$SEP read -r -a column_array <<< "$columns_d"
	IFS=$SEP read -r -a type_array <<< "$column_types_d"

	# Find index of $column,
	index=-1
	for i in "${!column_array[@]}"; do
    		if [[ "${column_array[$i]}" == "$column" ]]; then
			index=$i
        		break
    		fi
	done

	if [[ $index -ge 0 ]]; then
    		unset column_array[$index]
    		unset type_array[$index]
	fi

	# Rebuild orignal straings
	columns_d=$(IFS=$SEP; echo "${column_array[*]}")
	column_types_d=$(IFS=$SEP; echo "${type_array[*]}")
} # End column_delete
#--------------------------------------------------------------------------------------------------------#
function column_exists() {
	column=$1
	# Test if column exists in origin table
	column_exists=$(psql -U "$PG_USER" -d "$PG_DB2" -h "$PG_HOST2" -t -c "SELECT column_name FROM information_schema.columns WHERE table_name = '$table' AND column_name = '$column';")
} # End column_existe
#--------------------------------------------------------------------------------------------------------#
function id() {
	# copy id from origin table or create it
	column_exists 'id'
	if [[ -z "$column_exists" ]]; then
		id_select="SELECT row_number() AS id"
	else
		id_select="SELECT CAST(id AS INTEGER) AS id"
	fi
	id_constraint="ALTER TABLE $table ADD CONSTRAINT ${table}_pkey PRIMARY KEY (id);"
	column_delete 'id'
} # End id
#--------------------------------------------------------------------------------------------------------#
function document_id() {
	# create document_id
	column_exists 'document_id'
	if [[ -z "$column_exists" ]]; then
		document_id_select=",CAST(gen_random_uuid() AS VARCHAR(255)) AS document_id"
	else
		echo "document_id existe dans la table origine"
		exit 1
	fi
	column_delete 'document_id'
} # End document_id
#--------------------------------------------------------------------------------------------------------#
function created_at() {
	# copy created_at from origin table or create it
	column_exists 'created_at'
	if [[ -z "$column_exists" ]]; then
		created_at_select=",now() AS created_at"
	else
		created_at_select=",created_at"
	fi
	column_delete 'created_at'
} # End created_at
#--------------------------------------------------------------------------------------------------------#
function updated_at() {
	# copy updated_at from origin table or create it
	column_exists 'updated_at'
	if [[ -z "$column_exists" ]]; then
		updated_at_select=",Nulli::$ATT AS updated_at"
	else
		updated_at_select=",updated_at"
	fi
	column_delete 'updated_at'
} # End updated_at
#--------------------------------------------------------------------------------------------------------#
function deleted_at() {
	# copy deleted_at from origin table or create it
	column_exists 'deleted_at'
	if [[ -z "$column_exists" ]]; then
		deleted_at_select=",Null::$ATT AS deleted_at"
	else
		deleted_at_select=",deleted_at"
	fi
	column_delete 'deleted_at'
} # End deleted_at
#--------------------------------------------------------------------------------------------------------#
function published_at() {
	# copy published_at from origin table or create it
	column_exists 'published_at'
	if $PUBLISH; then
		if [[ -z "$column_exists" ]]; then
			published_at_select=",Null::$ATT AS published_at"
		else
			published_at_select=",published_at"
		fi
	else
		published_at_select=""
	fi
	column_delete 'published_at'
} # End of published_at
#--------------------------------------------------------------------------------------------------------#
function created_by_id() {
	# copy created_by_id from origin table or create it
	column_exists 'created_by_id'
	if [[ -z "$column_exists" ]]; then
		created_by_id_select=",Null::INTEGER AS created_by_id"
	else
		created_by_id_select=",created_by_id"
	fi
	column_delete 'created_by_id'
} # End created_by_id
#--------------------------------------------------------------------------------------------------------#
function updated_by_id() {
	# copy updated_by_id from origin table or create it
	column_exists 'updated_by_id'
	if [[ -z "$column_exists" ]]; then
		updated_by_id_select=",Null::INTEGER AS updated_by_id"
	else
		updated_by_id_select=",updated_by_id"
	fi
	column_delete 'updated_by_id'
} # End published_at
#--------------------------------------------------------------------------------------------------------#
function deleted_by_id() {
	# copy deleted_at from origin table or create it
	column_exists 'deleted_by_id'
	if [[ -z "$column_exists" ]]; then
		deleted_by_id_select=",Null::INTEGER AS deleted_by_id"
	else
		deleted_by_id_select=",deleted_by_id"
	fi
	column_delete 'deleted_by_id'
} # End deleted_at
#--------------------------------------------------------------------------------------------------------#
function locale() {
	# copy local from origin table or create it
	column_exists 'locale'
	if [[ -z "$column_exists" ]]; then
		locale_select=",Null::VARCHAR(255) AS locale"
	else
		locale_select=",locale"
	fi
	column_delete 'locale'
} # End locale
#--------------------------------------------------------------------------------------------------------#
function columns_d() {
	# build final select & dblink fields
	select=$id_select$document_id_select
	dblink_fields='id integer,document_id varchar(255)'
	IFS=$SEP read -r -a column_array <<< "$columns_d"
	IFS=$SEP read -r -a type_array <<< "$column_types_d"
	for i in "${!column_array[@]}"; do
		select=${select},${column_array[$i]}
    		dblink_fields=${dblink_fields},${column_array[$i]}" "${type_array[$i]} 
	done
	select=$select$created_at_select$updated_at_select$deleted_at_select$published_at_select$created_by_id_select$updated_by_id_select$deleted_by_id_select$locale_select
	if $PUBLISH; then
		published=",published_at $ATT"
	else
		published=""
	fi
	dblink_fields=$dblink_fields",created_at $ATT,updated_at $ATT,deleted_at $ATT$published,created_by_id integer,updated_by_id integer,deleted_by_id integer,locale varchar(255)"
} # End columns_d
#--------------------------------------------------------------------------------------------------------#
create_constrainsts() {
	# Indexes et contrainsts creation
	psql -U $PG_USER -d $PG_DB1 -h $PG_HOST1 -t -c "ALTER TABLE $table ADD PRIMARY KEY (id);"
	if $PUBLISH; then
		psql -U $PG_USER -d $PG_DB1 -h $PG_HOST1 -t -c "CREATE INDEX ${table}_document_id_idx ON $table (document_id,locale,published_at);"
	else
		psql -U $PG_USER -d $PG_DB1 -h $PG_HOST1 -t -c "CREATE INDEX ${table}_document_id_idx ON $table (document_id,locale);"
	fi
	psql -U $PG_USER -d $PG_DB1 -h $PG_HOST1 -t -c "ALTER TABLE $table ADD CONSTRAINT ${table}_created_by_id_fk FOREIGN KEY (created_by_id) REFERENCES admin_users(id);"
	psql -U $PG_USER -d $PG_DB1 -h $PG_HOST1 -t -c "ALTER TABLE $table ADD CONSTRAINT ${table}_updated_by_id_fk FOREIGN KEY (updated_by_id) REFERENCES admin_users(id);"
	psql -U $PG_USER -d $PG_DB1 -h $PG_HOST1 -t -c "ALTER TABLE $table ADD CONSTRAINT ${table}_deleted_by_id_fk FOREIGN KEY (deleted_by_id) REFERENCES admin_users(id);"
}
#--------------------------------------------------------------------------------------------------------#
function 2strapi_type() {
	type=$1
	s_type=$type
	s_plus=""
	s_minLength=""
	s_maxLength=""
	s_precision=""
	s_scale=""
# echo "2strapi_type type=$type"
	shared_types=(boolean date integer text)
	if [[ " ${shared_types[@]} " =~ " $type " ]]; then
		s_type=$type
	elif [[ "$type" == "character(1)" ]]; then
		s_type=string
		s_plus=","				
		s_minLength=1
		s_maxLength=1
	elif [[ "$type" == "character${SEP2}varying(64)" ]]; then
		s_type=string
		s_plus=","				
		s_maxLength=64
	elif [[ "$type" =~ "numeric" ]]; then
		s_type=decimal
		s_plus=","				
		s_precision=18
		s_scale=9
	else
		echo "db type ($type) must be mapped to strapi type in 2strapi_type function"
		exit 1	
	fi
# echo "2strapi_type s_type=$s_type"
} # End 2strapi_type
#--------------------------------------------------------------------------------------------------------#
function create_model() {
	# Strapi model creation
	model=${model_name}_shema.json
	echo '{
  "kind": "collectionType",
  "collectionName": "'$table'",
  "info": {
    "singularName": "'$model_name'",
    "pluralName": "'$table'",
    "displayName": "'$displayed_name'",
    "description": ""
  },
  "options": {
    "draftAndPublish": '$PUBLISH'
  },
  "pluginOptions": {},' > $model
	IFS=$SEP read -r -a column_array <<< "$columns_d"
	column_types_d2="${column_types_d// /$SEP2}"
	IFS=$SEP read -r -a type_array <<< "$column_types_d2"
	echo '  "attributes": {' >> $model
	last_index=$(( ${#column_array[@]} - 1 ))
	for i in "${!column_array[@]}"; do
		2strapi_type ${type_array[$i]}
		echo "    \"${column_array[$i]}\": {" >> $model
		echo "      \"type\": \"$s_type\"$s_plus" >> $model
		[[ -n "$s_minLength" ]] && echo "      \"minLength\": $s_minLength," >> $model
		[[ -n "$s_maxLength" ]] && echo "      \"maxLength\": $s_maxLength" >> $model
		[[ -n "$s_precision" ]] && echo "      \"precision\": $s_precision," >> $model
		[[ -n "$s_scale" ]] && echo "      \"scale\": $s_scale" >> $model
# echo ${type_array[$i]}
		if [ $i -eq $last_index ]; then
			echo "    }" >> $model
		else
			echo "    }," >> $model
		fi
	done
	echo "  }
}" >> $model
	# Transfer model to project
	destination_dir="$DIR1/src/api/$model_name/content-types/$model_name"
	mkdir -p $destination_dir
	cp $model $destination_dir/schema.json
} # End create_model
#--------------------------------------------------------------------------------------------------------#
function create_others() {
	# Créate Controller, route & service
	destination_dir=$DIR1/src/api/$model_name
	cd $destination_dir
	mkdir controllers
	mkdir routes
	mkdir services
	echo "/**
* $model_name controller
*/

import { factories } from '@strapi/strapi'

export default factories.createCoreController('api::$model_name.$model_name');" > controllers/$model_name.ts
	echo "/**
* $model_name router
*/

import { factories } from '@strapi/strapi';

export default factories.createCoreRouter('api::$model_name.$model_name');" > routes/$model_name.ts
	echo "/**
* $model_name service
*/

import { factories } from '@strapi/strapi';

export default factories.createCoreService('api::$model_name.$model_name');" > services/$model_name.ts
} # End create_others
#--------------------------------------------------------------------------------------------------------#
# Start
check_i					# Initial checks
columns_o				# Columns & types from origin table -> init destination fileds
id						# Copy or create id
document_id				# ...
created_at
updated_at
deleted_at
published_at
created_by_id
updated_by_id
deleted_by_id
locale
columns_d				# Columns & types of destination table
# cde to create destination table
cde0="CREATE TABLE $table AS (SELECT * FROM dblink('dbname=$PG_DB2 host=$PG_HOST2 user=$PG_USER','$select FROM $table') AS rt ($dblink_fields))"
cde="psql -U $PG_USER -d $PG_DB1 -h $PG_HOST1 -t -c \"$cde0\""

if $VERBOSE; then
echo "
	columns_and_types=$columns_and_types
	columns_o=$columns_o
	column_types_o=$column_types_o
	columns_d=$columns_d
	column_types_d=$column_types_d
	id_constraint=$id_constraint
	id_select=$id_select
	document_id_select=$document_id_select
	created_at_select=$created_at_select
	updated_at_select=$updated_at_select
	published_at_select=$published_at_select
	created_by_id_select=$created_by_id_select
	updated_by_id_select=$updated_by_id_select
	deleted_by_id_select=$deleted_by_id_select
	locale_select=$locale_select
	select=$select
	dblink_fields=$dblink_fields
	cde0=$cde0	
	cde=$cde	
"
fi

create_model				# before table creation to check types
# Create destination table
eval "$cde"
#
create_constrainsts
create_others
#
echo "All done."
