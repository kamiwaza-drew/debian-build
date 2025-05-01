#!/bin/bash
sudo bash wipe_linux_kz_install.sh --force-wipe 
echo "Wiped the linux kamiwaza install."
echo "########################################################"
echo "########################################################"
echo "########################################################"
echo "########################################################"
echo "########################################################"
echo "########################################################"
echo "INSTALLING THE NEW KAMIWAZA DEB PACKAGE"
echo "########################################################"
echo "########################################################"
echo "########################################################"
echo "########################################################"

# # Copy from remote to a temp directory
sudo scp -i /home/kamiwaza/.ssh/id_rsa kamiwaza@34.59.53.172:/home/kamiwaza/debian-packaging/kamiwaza_0.3.3-1_amd64.deb /home/kamiwaza/


# Remove old kamiwaza package before installing new one
sudo apt-get remove --purge -y kamiwaza || true
sudo apt-get clean
sudo apt-get update

# #`` Install the deb package
sudo apt install -y /home/kamiwaza/kamiwaza_0.3.3-1_amd64.deb


# IF NEEDED, UNCOMMENT THE FOLLOWING LINES AND RUN THE SCRIPT:
# scp -i ~/.ssh/id_rsa kamiwaza@34.59.53.172:/home/kamiwaza/kamiwaza-deploy/linux-install.sh ~/
# # Do the same for linux-permissions.sh, common.sh and install.sh
# scp -i ~/.ssh/id_rsa kamiwaza@34.59.53.172:/home/kamiwaza/kamiwaza-deploy/linux-permissions.sh ~/
# scp -i ~/.ssh/id_rsa kamiwaza@34.59.53.172:/home/kamiwaza/kamiwaza-deploy/common.sh ~/
# scp -i ~/.ssh/id_rsa kamiwaza@34.59.53.172:/home/kamiwaza/kamiwaza-deploy/install.sh ~/
# transfer python3.10-stdlib.tar.gz 
# scp -i ~/.ssh/id_rsa kamiwaza@34.59.53.172:/home/kamiwaza/debian-packaging/python3.10-stdlib-full.tar.gz ~/


# TO RUN THIS SCRIPT:
# bash get_new_kmz.sh
