#!/bin/bash
#
# Written by ahmed.sajid
# https://github.com/ahmedsajid/spacewalk
# Version 1.0
# Modified by RickMulder 8/1/2017
# https://github.com/rickymulder/spacewalk
# Version 1.1
#
# Most of these instructions are taken from https://access.redhat.com/articles/1355053
#
# This script downloads repos using reposync from Red Hat.
# Repodata is created using createrepo
# After all the repos are sycned locally, these are then sync into spacewalk
# Make sure you have /etc/yum.repos.d/redhat.repo file present with correct URLs pointing to RHEL 6 repos

echo "--------------------------------------------------"
echo "Start: $(date +\"%d-%b-%Y\ %T\")    Host: $(hostname)"
echo "--------------------------------------------------"

# List of REPOS to sync from Red Hat
RHEL6_REPOS="rhel-6-server-rpms rhel-6-server-extras-rpms rhel-6-server-optional-rpms rhel-6-server-rh-common-rpms rhel-6-server-supplementary-rpms"
EPEL_REPO="epel-rhel6-x86_64"

# Path to local repo directory
REPO_DIR="/var/satellite/reposync"

# Check if yum-utils and createrepo is installed
if ! rpm -qa | grep -q "yum-utils\|createrepo";then
  echo "Please install yum-utils and createrepo before running this script again"
  echo "yum install yum-utils createrepo"
  exit 1
fi

# Check if redhat.repo file exists
if [ ! -f /etc/yum.repos.d/redhat.repo ];then
  echo "Redhat repo file doesn't exist /etc/yum.repos.d/redhat.repo"
  exit 1
fi

# loop through list of REPOS, sync them locally and create repodata
for REPO in $RHEL6_REPOS $EPEL_REPO
do

  echo "--------------------------------------------------"
  echo "$REPO: - reposync starting - $(date +\"%d-%b-%Y\ %T\")"
  echo "--------------------------------------------------"

  # Syncing repositories locally
  # Remove newest-only to create an exact mirror of Red Hat repos. This is used to save disk space
  # Remove quiet for debugging
  reposync --quiet --downloadcomps --download-metadata --newest-only --delete --arch x86_64 --download_path $REPO_DIR/ --repoid $REPO

  # Creates repodata folder
  createrepo --quiet --checksum sha256 --checkts --update --workers=2 --groupfile $REPO_DIR/$REPO/comps.xml $REPO_DIR/$REPO

  # If productid.gz exists extract it
  if [ -f $REPO_DIR/$REPO/productid.gz ];then
    gunzip $REPO_DIR/$REPO/productid.gz
  # update repomd.xml file with productid
    modifyrepo $REPO_DIR/$REPO/productid $REPO_DIR/$REPO/repodata/
  fi

  # extract updateinfo file
  set -o pipefail
  if ls $REPO_DIR/$REPO/*updateinfo.xml.gz 2>/dev/null | tail -n 1 ; then
    echo "updateinfo.xml.gz found"
    gunzip -c $(ls -rt $REPO_DIR/$REPO/*updateinfo.xml.gz | tail -n 1) > $REPO_DIR/$REPO/updateinfo.xml
  else
    echo "updateinfo.xml.gz not found"
    file=$(curl -s https://dl.fedoraproject.org/pub/epel/6Server/x86_64/repodata/ | grep "updateinfo.xml.bz2" | cut -d'"' -f6)
    echo "Downloading EPEL $file"
    wget -q -P $REPO_DIR/$REPO/ https://dl.fedoraproject.org/pub/epel/6Server/x86_64/repodata/$file
                bunzip2 -c $(ls -rt $REPO_DIR/$REPO/*updateinfo.xml.bz2 | tail -n 1) > $REPO_DIR/$REPO/updateinfo.xml
  fi

  # Patch updateinfo file https://bugzilla.redhat.com/show_bug.cgi?id=1354496
  # line cause the problem
  # for e.g.,
  # <reference href="https://bugzilla.redhat.com/show_bug.cgi?id=1148230" type="bugzilla" id="RHSA-2014:1801" title="CVE-2014-3675 shim: out-of-bounds memory read flaw in DHCPv6 packet processing" />
  # should be
  # <reference href="https://bugzilla.redhat.com/show_bug.cgi?id=1148230" type="bugzilla" id="1148230" title="CVE-2014-3675 shim: out-of-bounds memory read flaw in DHCPv6 packet processing" />
  # Spacewalk doesn't like it for obvious reason
  # If this patch isn't applied, erratas dont get synced and you will get an error something similar to the following while running spacewalk-repo-sync
  # ERROR: invalid literal for int() with base 10: 'RHSA-2014:1801'

  sed -i 's/=\([0-9]*\)\(" type="bugzilla" id="\)RH[BSE]A-[0-9]\{4\}:[0-9]\{4\}/=\1\2\1/' $REPO_DIR/$REPO/updateinfo.xml

  # update repomd.xml with new updateinfo.xml
  modifyrepo $REPO_DIR/$REPO/updateinfo.xml $REPO_DIR/$REPO/repodata/

  # change permissions on repo directory
  chmod 755 $REPO_DIR/$REPO/repodata
  chmod 644 $REPO_DIR/$REPO/repodata/*
done
# Changing ownership to apache for /opt/repos
chown -R apache: $REPO_DIR

# List of RHEL6 & RHEL7 channels to sync into spacewalk, that already exist
RHEL6_CHANNELS="subscription_manager"

# Loop through the channels and run spacewalk-repo-sync
for CHANNEL in $RHEL6_CHANNELS
do
  echo "--------------------------------------------------"
  echo "$CHANNEL: - spacewalk-repo-sync starting - $(date +\"%d-%b-%Y\ %T\")"
  echo "--------------------------------------------------"
    spacewalk-repo-sync --channel $CHANNEL
done

echo "--------------------------------------------------"
echo "Finish: $(date +\"%d-%b-%Y\ %T\")   Host: $(hostname)"
echo "--------------------------------------------------"
