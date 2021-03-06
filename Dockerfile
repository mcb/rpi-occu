FROM 	marbon87/rpi-java
MAINTAINER Mark Bonnekessel <marbon@mailbox.org>

#       Install packages------------------------------------------------------
RUN 	apt-get update && apt-get install -y \
        msmtp \
        tcl \
        tcllib \
        libusb-1.0-0-dev \
        unzip \
        rsyslog \
        cron \
        man \
        netbase \
        --no-install-recommends && \
        rm -rf /var/lib/apt/lists/*

#       Activate systemd
ENV     INITSYSTEM on

#       Preparation-----------------------------------------------------------
RUN     mkdir -p /opt/hm && mkdir -p /root/temp 
WORKDIR /root/temp

ENV     HM_HOME=/opt/hm
ENV     LD_LIBRARY_PATH=$HM_HOME/lib

#       Download and unpack occu----------------------------------------------
ENV     OCCU_VERSION 2.17.15
RUN     wget -O occu.zip https://github.com/eq-3/occu/archive/${OCCU_VERSION}.zip ; unzip -q occu.zip; rm occu.zip

#       Copy file to /opt/hm---------------------------------------------------
WORKDIR /root/temp/occu-${OCCU_VERSION}/arm-gnueabihf
RUN     ./install.sh
RUN     chmod +x /opt/hm/bin/eq3configcmd
RUN     ln -sf /opt/hm/bin/* /bin/ && ln -sf /opt/hm/lib/* /lib/
WORKDIR /root/temp/occu-${OCCU_VERSION}
RUN     mv /opt/hm/etc/config /usr/local/etc
RUN     ln -s /usr/local/etc/config /opt/hm/etc && ln -s /usr/local/etc/config /etc
RUN     cp -a firmware /opt/hm
RUN     mkdir -p /etc/config/firmware
RUN     cp -a HMserver/etc/config_templates/log4j.xml /opt/hm/etc/config && cp -a HMserver/opt/HMServer /opt
RUN     sed -i "s|INFO|WARN|g" /opt/hm/etc/config/log4j.xml
RUN     cp -a scripts/debian/init.d/* /etc/init.d

#       Add default config-----------------------------------------------------
ADD     ./config/ /etc/config/

#       Configure rfd----------------------------------------------------------
RUN     systemctl enable rfd

#       lighttpd--------------------------------------------------------------
RUN     systemctl enable lighttpd
RUN     sed -i "s|#server.errorlog-use-syslog|server.errorlog-use-syslog|g" $HM_HOME/etc/lighttpd/lighttpd.conf

#       lighttpd:configure ssl------------------------------------------------
RUN     cp /etc/init.d/lighttpd /etc/init.d/lighttpd_ssl
RUN     sed -i "s|# Provides:          lighttpd|# Provides:          lighttpd_ssl|g" /etc/init.d/lighttpd_ssl
RUN     sed -i "s|NAME=lighttpd|NAME=lighttpd_ssl|g" /etc/init.d/lighttpd_ssl
RUN     sed -i "s|DAEMON=\$HM_HOME/bin/\$NAME|DAEMON=\$HM_HOME/bin/lighttpd|g" /etc/init.d/lighttpd_ssl
RUN     sed -i "s|lighttpd.conf|lighttpd_ssl.conf|g" /etc/init.d/lighttpd_ssl
RUN     sed -i "s|lighttpd.pid|lighttpd_ssl.pid|g" /opt/hm/etc/lighttpd/lighttpd_ssl.conf
RUN     systemctl enable lighttpd_ssl

#       ReGaHss---------------------------------------------------------------
WORKDIR /root/temp/occu-${OCCU_VERSION}/WebUI
RUN     cp -a bin www /opt/hm
RUN     echo "VERSION=${OCCU_VERSION}" > /boot/VERSION
RUN     ln -s /opt/hm/www /www
RUN     systemctl enable regahss

## Allow restart of rsyslog
RUN     sed -i "s|catch {exec killall syslogd}|#catch {exec killall syslogd}|g" /opt/hm/www/config/cp_maintenance.cgi 
RUN     sed -i "s|catch {exec killall klogd}|#catch {exec killall klogd}|g" /opt/hm/www/config/cp_maintenance.cgi 
RUN     sed -i "s|exec /etc/init.d/S01logging start|exec systemctl restart rsyslog|g" /opt/hm/www/config/cp_maintenance.cgi 

#       HMServer--------------------------------------------------------------
WORKDIR /root/temp/occu-${OCCU_VERSION}/HMserver
RUN     ln -s /opt/hm/etc/crRFD.conf /etc/crRFD.conf 
RUN     echo "#!/bin/sh\n### BEGIN INIT INFO\n# Provides:          HMserver\n# Required-Start:    \$network \$remote_fs \$syslog\n# Required-Stop:     \$network \$remote_fs \$syslog\n# Default-Start:     2 3 4 5\n# Default-Stop:      0 1 6\n# Short-Description: HomeMatic HMserver service\n# Description:       HomeMatic HMserver service\n### END INIT INFO\n" "$(tail -n +5 ./etc/init.d)" > /etc/init.d/HMserver
RUN     chmod +x /etc/init.d/HMserver
RUN     sed -i "s|java|${JAVA_HOME}/bin/java|g" /etc/init.d/HMserver
RUN     systemctl enable HMserver

#       Modifications for backup,restore and add-on installation--------------
ADD     ./bin /bin
RUN     chmod +x  /bin/crypttool /bin/firmware_update.sh
RUN     sed -i "s|exec /bin/kill -SIGQUIT 1|#exec /bin/kill -SIGQUIT 1\n        # OCCU: Erst noch die homematic.regadom sichern\n        rega system.Save()\n        # OCCU: Then execute firmware update script\n        exec /bin/firmware_update.sh|g" /opt/hm/www/config/cp_software.cgi
RUN     sed -i "s|exec umount /usr/local|#exec umount /usr/local|g"  /opt/hm/www/config/cp_security.cgi && \
sed -i "s|exec /usr/sbin/ubidetach -p /dev/mtd6|#exec /usr/sbin/ubidetach -p /dev/mtd6|g"  /opt/hm/www/config/cp_security.cgi && \
sed -i "s|exec /usr/sbin/ubiformat /dev/mtd6 -y|#exec /usr/sbin/ubiformat /dev/mtd6 -y|g"  /opt/hm/www/config/cp_security.cgi && \
sed -i "s|exec /usr/sbin/ubiattach -p /dev/mtd6|#exec /usr/sbin/ubiattach -p /dev/mtd6|g"  /opt/hm/www/config/cp_security.cgi && \
sed -i "s|exec /usr/sbin/ubimkvol /dev/ubi1 -N user -m|#exec /usr/sbin/ubimkvol /dev/ubi1 -N user -m|g"  /opt/hm/www/config/cp_security.cgi && \
sed -i "s|exec mount /usr/local|#exec mount /usr/local|g"  /opt/hm/www/config/cp_security.cgi && \
sed -i "s|exec kill -SIGQUIT 1|reboot|g"  /opt/hm/www/config/cp_security.cgi && \
sed -i "s|exec mount -o remount,ro /usr/local|#exec mount -o remount,ro /usr/local|g"  /opt/hm/www/config/cp_security.cgi && \
sed -i "s|exec mount -o remount,rw /usr/local|#exec mount -o remount,rw /usr/local|g"  /opt/hm/www/config/cp_security.cgi
RUN     echo SerialNumber=rpi-occu > /var/ids

#       Simulate sd-card------------------------------------------------------
RUN     mkdir -p /media/sd-mmcblk0/measurement && \
        mkdir -p /opt/HMServer/measurement && \
        mkdir -p /etc/config/measurement && \
        mkdir -p /var/status && \
        touch /var/status/hasSD && \
        touch /var/status/SDinitialised && \
        touch /media/sd-mmcblk0/.initialised

#       Fix time settings-----------------------------------------------------
RUN     (crontab -l ; echo "*/30 * * * * /opt/hm/bin/SetInterfaceClock 127.0.0.1:2001") | sort - | uniq - | crontab -

#       Allow to configure logging from webgui--------------------------------
RUN     sed -i "s|/bin/sh|/bin/bash|g" /etc/init.d/rfd && \
sed -i "s|/bin/sh|/bin/bash|g" /etc/init.d/regahss && \
sed -i "s|LOGLEVEL_RFD=0|if [ -f /usr/local/etc/config/syslog ] ; then source /usr/local/etc/config/syslog ; else LOGLEVEL_RFD=0 ; fi|g" /etc/init.d/rfd && \
sed -i "s|LOGLEVEL_REGAHSS=0|if [ -f /usr/local/etc/config/syslog ] ; then source /usr/local/etc/config/syslog ; else LOGLEVEL_REGA=0 ; fi|g" /etc/init.d/regahss && \
sed -i "s|LOGLEVEL_REGAHSS|LOGLEVEL_REGA|g" /etc/init.d/regahss 

#       create folder for addons----------------------------------------------
RUN     mkdir -p /usr/local/etc/config/rc.d

#       move back to /root----------------------------------------------------
WORKDIR /root
#       cleanup a bit---------------------------------------------------------
RUN     apt-get clean && apt-get purge

