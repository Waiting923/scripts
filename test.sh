HOSTNAME=$(hostname | cut -c1-7)
if [ $HOSTNAME = storage ]
then
	echo 1
else 
	echo 2
fi
