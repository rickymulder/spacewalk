# Spacewalk

## nightly_sync.sh
This script is designed to create a local copy of relevant repos on your spacewalk server.
You will need to make the directory accessible via apache for spacewalk to be able to sync against it.
Due to EPEL's handling of errata data (updateinfo.xml), the script downloads the data manually.
