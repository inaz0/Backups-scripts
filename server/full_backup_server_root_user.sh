#!/bin/bash
#
# Description: script de backup de serveur avant complet
# Inazo <inazo.wh@gmail.com>
# Version: 1.1
# Date: 2020-02-25
# Update: 2020-08-11
#
# Instruction: Run as root
#
# Changelog:
#
# 1.1: 
#	- add data and structure dump control for MySQL dump
#	- add backup for root folder
#	- add remove temp folder after backup
# 1.0: initial version
#

echo "Starting full backup of this server..."
echo ""

pathBackup='/var/full_backup'

mkdir $pathBackup

# si MySQL est en --secure-file-priv il faut bien envoyer les bases au bon endroit
mkdir -p /var/lib/mysql-files/dump
bddPathDump='/var/lib/mysql-files/dump'


echo "Give root password for MySQL:"
read -s databasePassword


#récupération du nom d'hote et création des noms des fichiers de log des dumps
host=`cat /etc/hostname`
sqlLog=$pathBackup'/'$host'_'`date +%Y-%m-%d`.structure.log
sqlLogData=$pathBackup'/'$host'_'`date +%Y-%m-%d`.data.log

#Fonction de test de dump SQL pour savoir si les fichiers sont bien créé à la date du jour
#Sera aussi utilisé pour loguer les tables sans donnees
function checkDumpDatabase() {


	fileToCheck=$1	
	sqlLog=$2	
	
	
	statFile=`stat --format=%y $fileToCheck`
	statFileSize=`stat --format=%s $fileToCheck`

	currentDate="$(date +'%Y-%m-%d')"

	if [[ $statFile =~ $currentDate(.*) ]]; then

			if [[ $statFileSize == 0 ]]; then

				# Si on a un troisieme argument on est sur le controle des donnees, on va donc faire un count de la table et s'il y a 0 ligne on leve pas d'erreur
				if [ -n $4 ]; then

					dbName=$4

					filename=$(basename -- "$fileToCheck")
					extension="${filename##*.}"
					filename="${filename%.*}"

					# on va chercher pour cette base cette table -B pas de formattage en tableau en sortie et -N pas de nom de colonne donc juste la valeur
					numberResult=`mysql -u root -p$3 -B -N -e "SELECT COUNT(*) FROM \\\`$dbName\\\`.$filename"`

					# si on a un resultat different de zero il y a un souci !
					if [ $numberResult -ne "0" ]; then
						`echo "$fileToCheck: size of file error : 0B" >> "$sqlLog"`
					fi
				else
					`echo "$fileToCheck: size of file error : 0B" >> "$sqlLog"`
				fi
			fi

	else
		`echo "$fileToCheck: Not modified this day" >> "$sqlLog"`
	fi
}

# récupération des base de données direct en sudo pas besoin de password pour root
databases=`sudo mysql -u root -p$databasePassword -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|mysql|performance_schema|phpmyadmin)"`


for db in $databases; do

	echo "|__ Start dumping for: $db..."
    
    mkdir -p $bddPathDump/$db
    chmod 777 $bddPathDump/$db

	# un fichier pour uniquement les procédures
	mysqldump -u root -p$databasePassword $db -l --no-data --routines --no-create-info --skip-triggers > "$bddPathDump/$db/$db-routines".sql
		
	#structure complete de la base avec les vues
	mysqldump -u root -p$databasePassword $db -l --no-data --triggers > "$bddPathDump/$db/$db-structures.sql"

	#Un fichier txt par table pour uniquement les données
	mysqldump -u root -p$databasePassword $db -l --tab=/tmp --fields-terminated-by=, --fields-optionally-enclosed-by='"' --lines-terminated-by=0x0d0a -T $bddPathDump/$db
		
	# un fichier avec tout
	mysqldump --force --opt -u root -p$databasePassword --add-drop-database --add-drop-table --complete-insert --routines --triggers --max_allowed_packet=250M --force --databases $db > "$bddPathDump/$db/$db-full".sql
	
	echo "|__ End dumping for: $db..."

	#Controle du bon fonctionnement du backup
	find "$bddPathDump/$db/" -type f -name \*.sql | while read file; do checkDumpDatabase $file $sqlLog $databasePassword; done
	find "$bddPathDump/$db/" -type f -name \*.txt | while read file; do checkDumpDatabase $file $sqlLogData $databasePassword $db; done
	
done

#on va juste avoir besoin plus du nom uniquement
archiveName=`date +%Y-%m-%d`.tar.gz

echo "|__ Merge dumps..."
# on récupère nos dumps de base
tar czf $pathBackup/sql_$archiveName $bddPathDump

echo "|__ Tar etc folder ..."
# on récupère tous ce que l'on a dans etc surtout les conf
tar czf $pathBackup/etc_$archiveName /etc/

echo "|__ Tar cron folder ..."
# On ajoute les fichiers cron au backup
tar czf $pathBackup/cron_$archiveName /var/spool/cron/crontabs/

echo "|__ Tar www folder ..."
# Le contenu du répértoire www car c'était un serveur Web
tar czf $pathBackup/www_$archiveName /var/www/

echo "|__ Tar home folder ..."
# Le contenu des dossiers home ou cas ou on aurait des users avec des fichiers qu'on veux éviter de perdre
tar czf $pathBackup/home_$archiveName /home/

echo "|__ Tar root folder ..."
# Le contenu du dossier root ça serait là aussi dommage de perdre des scripts précieux
tar czf $pathBackup/root_$archiveName /root/


echo "|__ Tar backup folder ..."
# Et pour finir on regroupe tout en une archive
tar czf full_backup_$archiveName $pathBackup

echo ""
echo "Deleting $pathBackup"
rm -rf $pathBackup

echo ""
echo "Full backup was terminated."


