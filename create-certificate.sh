#!/bin/bash

SSLDIR=/tmp/openssl
LINE="---------------------------------------------------------------------------------------------------------"
IPADDR=`hostname -I`
LONGNAME=`hostname --fqdn`
SHORTNAME=`hostname -s`

##################################################################################
### Remove old files if they exist
##################################################################################
clear
echo $LINE
if [ -d $SSLDIR ]
then
        for i in conf csr out
        do
                if [ -d "$SSLDIR/$i" ]
                then
                        echo "Removing $SSLDIR/$i and all files"
                        rm -rf $SSLDIR/$i
                fi
        done
fi

if [ ! -d $SSLDIR ]
then
        mkdir $SSLDIR
fi
mkdir $SSLDIR/out $SSLDIR/conf $SSLDIR/csr

##################################################################################
### Verify these are the right IP And FQDN
##################################################################################
echo $LINE

echo "Are the following correct?"
echo "IP Address: $IPADDR"
echo "FQDN: $LONGNAME"
echo "SHRT: $SHORTNAME"
echo ""
read -p "Are you sure? " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
fi

##################################################################################
### Create CA Config File
##################################################################################
echo $LINE
echo "Create CA Config File"

cat <<EOF > $SSLDIR/conf/ca.cnf
[ ca ]
default_ca = CA_default

[ CA_default ]
serial = ca-serial
crl = ca-crl.pem
database = ca-database.txt
name_opt = CA_default
cert_opt = CA_default
default_crl_days = 999
default_md = md5

[ req ]
days = 999
distinguished_name = req_distinguished_name
attributes = req_attributes
prompt = no
output_password = password

[ req_distinguished_name ]
C = US
ST = US
L = RTP
O = netapp.com
OU = IT Department
CN = vsadmin
emailAddress = nobody@netapp.com

[ req_attributes ]
challengePassword = password
EOF
##################################################################################
### Create the Certificate Sign Request Host Extension File
##################################################################################
echo $LINE
echo "Create the Certificate Sign Request Host Extension File"

cat <<EOF > $SSLDIR/conf/host.v3.ext
extendedKeyUsage = critical, serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $LONGNAME
DNS.2 = $SHORTNAME
IP.1 = $IPADDR
EOF

##################################################################################
### Create Certificate Sign Request Config File
##################################################################################
echo $LINE
echo "Create Certificate Sign Request Config File"

cat <<EOF > $SSLDIR/conf/host.cnf
[req] 
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
C = US
ST = North Carolina
L = RTP
O = NetApp.com
OU = IT Department
CN = vsadmin
emailAddress = nobody@netapp.com

EOF

##################################################################################
### Create new self-signed request
##################################################################################
echo $LINE
echo "Create new self-signed request"
openssl req -new -x509 -days 999 -config ${SSLDIR}/conf/ca.cnf -keyout ${SSLDIR}/out/ca-key.pem -out ${SSLDIR}/out/ca.pem


##################################################################################
### Generate private key
##################################################################################
echo $LINE
echo "Generate private key"
openssl genpkey -out ${SSLDIR}/out/host-key.pem -algorithm RSA -pkeyopt rsa_keygen_bits:2048

##################################################################################
### Generate Cert Sign Request with private key and config file
##################################################################################
echo $LINE
echo "Generate Cert Sign Request with private key and config file"
openssl req -new -config ${SSLDIR}/conf/host.cnf -key ${SSLDIR}/out/host-key.pem -out ${SSLDIR}/csr/host-csr.pem


##################################################################################
### Sign the Cert Sign Request with the CA
##################################################################################
echo $LINE
echo "Sign the Cert Sign Request with the CA"
openssl x509 -req -extfile ${SSLDIR}/conf/host.v3.ext -days 99 -passin "pass:password" -sha256 -in ${SSLDIR}/csr/host-csr.pem -CA ${SSLDIR}/out/ca.pem -CAkey ${SSLDIR}/out/ca-key.pem -CAcreateserial -out ${SSLDIR}/out/host-crt.pem

##################################################################################
### Combine certificate with private key
##################################################################################
echo $LINE
echo "Combine certificate with private key"
cat ${SSLDIR}/out/host-crt.pem ${SSLDIR}/out/host-key.pem > ${SSLDIR}/out/host.cert

##################################################################################
### Store the signed cert and public certs
##################################################################################
echo $LINE
echo "Store the signed cert and public certs"
cp -rp ${SSLDIR}/out/{host.cert,ca.pem} /opt/netapp/max/certificates/

##################################################################################
### Link Certs
##################################################################################
echo $LINE
echo "Link Certs"
ln -sf /opt/netapp/max/certificates/host.cert /etc/max/dashboard/config/signed.pem
ln -sf /opt/netapp/max/certificates/ca.pem /etc/max/dashboard/config/ca.pem

##################################################################################
### Check and Restart max-dashboard service
##################################################################################
echo $LINE
echo "Restarting MAX Dashboard Service"
systemctl restart max-dashboard
echo $LINE
echo "Checking MAX Dashboard Service"
systemctl status max-dashboard

