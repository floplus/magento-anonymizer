#!/bin/bash
echo "*** This script is anonymizing a DB-dump of the LIVE-DB in the DEMO-Environment ***"

PATH_TO_ROOT=$1
if [[ "$PATH_TO_ROOT" == "" && -f "app/etc/env.php" ]]; then
  PATH_TO_ROOT="."
fi
if [[ "$PATH_TO_ROOT" == "" ]]; then
  echo "Please specify the path to your Magento store"
  exit 1
fi
CONFIG=$PATH_TO_ROOT"/.anonymizer.cfg"

if [[ 1 < $# ]]; then
  if [[ "-c" == "$1" ]]; then
    PATH_TO_ROOT=$3
    CONFIG=$2
    if [[ ! -f $CONFIG ]]; then
      echo -e "\E[1;31mCaution: \E[0mConfiguration file $CONFIG does not exist, yet! You will be asked to create it after the anonymization run."
      echo "Do you want to continue (Y/n)?"; read CONTINUE;
      if [[ ! -z "$CONTINUE" && "$CONTINUE" != "y" && "$CONTINUE" != "Y" ]]; then
        exit;
      fi
    fi
  fi
fi


while [[ ! -f $PATH_TO_ROOT/app/etc/env.php ]]; do
  echo "$PATH_TO_ROOT is no valid Magento root folder. Please enter the correct path:"
  read PATH_TO_ROOT
done

HOST_PORT=`php -r "\\$env = include '${PATH_TO_ROOT}/app/etc/env.php'; print_r(\\$env['db']['connection']['default']['host']);"`

HOST="$(echo $HOST_PORT | cut -d':' -f1)"
PORT="$(echo $HOST_PORT | cut -d':' -f2)"

if [ "$HOST" = "$PORT" ]; then
    PORT="";
fi

USER=`php -r "\\$env = include '${PATH_TO_ROOT}/app/etc/env.php'; print_r(\\$env['db']['connection']['default']['username']);"`
PASS=`php -r "\\$env = include '${PATH_TO_ROOT}/app/etc/env.php'; print_r(\\$env['db']['connection']['default']['password']);"`
NAME=`php -r "\\$env = include '${PATH_TO_ROOT}/app/etc/env.php'; print_r(\\$env['db']['connection']['default']['dbname']);"`

if [[ -f "$CONFIG" ]]; then
  echo "Using configuration file $CONFIG"
  source "$CONFIG"
fi

if [[ -z "$DEV_IDENTIFIERS" ]]; then
  DEV_IDENTIFIERS=".*(dev|stage|staging|test|anonym).*"
fi
if [[ $NAME =~ $DEV_IDENTIFIERS ]]; then
    echo "We are on the TEST environment, everything is fine"
else
    echo ""
    echo "IT SEEMS THAT WE ARE ON THE PRODUCTION ENVIRONMENT!"
    echo ""
    echo "If you are sure, this is a test environment, please type 'test' to continue"
    read force
    if [[ "$force" != "test" ]]; then
        echo "Canceled"
        exit 2
    fi
fi

DBCALL="mysql -u$USER -h$HOST";

if [ "$PASS" != "" ]; then
    DBCALL=" $DBCALL -p$PASS"
fi

if [ "$PORT" != "" ]; then
    DBCALL=" $DBCALL --port=$PORT"
fi


DBCALL="$DBCALL -h$HOST $NAME -e"

echo "* Step 1: Anonymize Names and eMails"

if [[ -z "$RESET_ADMIN_PASSWORDS" ]]; then
  echo "  Do you want me to reset admin user passwords (Y/n)?"; read RESET_ADMIN_PASSWORDS
fi
if [[ "$RESET_ADMIN_PASSWORDS" == "y" || "$RESET_ADMIN_PASSWORDS" == "Y" || -z "$RESET_ADMIN_PASSWORDS" ]]; then
  RESET_ADMIN_PASSWORDS="y"
  # admin user
  $DBCALL "UPDATE admin_user SET password=MD5(CONCAT(username,'123',':0'))"
else
  RESET_ADMIN_PASSWORDS="n"
fi

#if [[ -z "$RESET_API_PASSWORDS" ]]; then
#  echo "  Do you want me to reset API user passwords (Y/n)?"; read RESET_API_PASSWORDS
#fi
#if [[  "$RESET_API_PASSWORDS" == "y" || "$RESET_API_PASSWORDS" == "Y" || -z "$RESET_API_PASSWORDS" ]]; then
#  RESET_API_PASSWORDS="y"
#  # api user
#  $DBCALL "UPDATE api_user SET api_key=MD5(CONCAT(username,'123'))"
#else
#  RESET_API_PASSWORDS="n"
#fi

if [[ -z "$ANONYMIZE" ]]; then
  echo "  Do you want me to anonymize your database (Y/n)?"; read ANONYMIZE
fi
if [[ "$ANONYMIZE" == "y" || "$ANONYMIZE" == "Y" || -z "$ANONYMIZE" ]]; then
  ANONYMIZE="y"
  # customer address
#  ATTR_CODE="firstname"
#  $DBCALL "UPDATE customer_address_entity SET value=CONCAT('firstname_',entity_id)"
  $DBCALL "UPDATE customer_address_entity SET lastname=CONCAT('lastname_',entity_id)"
  $DBCALL "UPDATE customer_address_entity SET telephone=CONCAT('0123 12345',entity_id)"
  $DBCALL "UPDATE customer_address_entity SET fax=CONCAT('0123 12345-1',entity_id)"
  $DBCALL "UPDATE customer_address_entity SET street=CONCAT('test avenue ', entity_id)"

  # customer account data
  if [[ -z "$KEEP_EMAIL" ]]; then
    echo "  If you want to keep some users credentials, please enter corresponding email addresses quoted by '\"' separated by comma (default: none):"; read KEEP_EMAIL
  fi
  ERRORS_KEEP_MAIL=`echo "$KEEP_EMAIL" | grep -vP -e '(\"[^\"]+@[^\"]+\")(, ?(\"[^\"]+@[^\"]+\"))*'`
  if [[ ! -z "$ERRORS_KEEP_MAIL" && "$KEEP_EMAIL" != '"none"' ]]; then
    while [[ ! -z "$errors_keep_mail" ]]; do
      echo -e "\e[1;31minvalid input! \E[0mExample: \"foo@bar.com\",\"me@example.com\"."
      echo "  If you want to keep some users credentials, please enter corresponding email addresses quoted by '\"' separated by comma (default: none):"; read KEEP_EMAIL
      ERRORS_KEEP_MAIL=`echo "$KEEP_EMAIL" | grep -vP -e '(\"[^\"]+@[^\"]+\")(, ?(\"[^\"]+@[^\"]+\"))*'`
      if [[ -z "$KEEP_MAIL" ]]; then
        break
      fi
    done
    if [[ ! -z "$KEEP_EMAIL" ]]; then
      echo "  Keeping $KEEP_EMAIL"
    fi
  else
    KEEP_EMAIL='"none"'
  fi

  $DBCALL "UPDATE customer_entity SET email=CONCAT('dev_',entity_id,'@trash-mail.com') WHERE email NOT IN ($KEEP_EMAIL)"
#  $DBCALL "UPDATE customer_entity SET firstname=CONCAT('firstname_',entity_id)"
  $DBCALL "UPDATE customer_entity SET lastname=CONCAT('lastname_',entity_id)"
  ATTR_CODE="password_hash"
  $DBCALL "UPDATE customer_entity SET password_hash=MD5(CONCAT('dev_',entity_id,'@trash-mail.com', ':0')) WHERE email NOT IN ($KEEP_EMAIL)"

  $DBCALL "UPDATE customer_grid_flat SET name=CONCAT('name_',entity_id)"
  $DBCALL "UPDATE customer_grid_flat SET email=CONCAT('dev_',entity_id,'@trash-mail.com')"
  $DBCALL "UPDATE customer_grid_flat SET shipping_full=CONCAT('shipping_',entity_id)"
  $DBCALL "UPDATE customer_grid_flat SET billing_full=CONCAT('billing_',entity_id)"
  $DBCALL "UPDATE customer_grid_flat SET billing_firstname=CONCAT('firstname_',entity_id)"
  $DBCALL "UPDATE customer_grid_flat SET billing_lastname=CONCAT('lastname_',entity_id)"
  $DBCALL "UPDATE customer_grid_flat SET billing_telephone=CONCAT('telefone_',entity_id)"
  $DBCALL "UPDATE customer_grid_flat SET billing_street=CONCAT('street_',entity_id)"
  $DBCALL "UPDATE customer_grid_flat SET billing_fax='0123 12345-1' WHERE billing_fax != ''"
  $DBCALL "UPDATE customer_grid_flat SET billing_company=CONCAT('company_',entity_id) WHERE billing_company != ''"

  # credit memo
  $DBCALL "UPDATE sales_creditmemo_grid SET billing_name='Demo User'"

  # invoices
  $DBCALL "UPDATE sales_invoice_grid SET billing_name='Demo User'"

  # shipments
  $DBCALL "UPDATE sales_shipment_grid SET shipping_name='Demo User'"

  # quotes
  $DBCALL "UPDATE quote SET customer_email=CONCAT('dev_',entity_id,'@trash-mail.com'), customer_firstname='Demo', customer_lastname='User', customer_middlename='Dev', remote_ip='192.168.1.1', password_hash=NULL WHERE customer_email NOT IN ($KEEP_EMAIL)"
  $DBCALL "UPDATE quote_address SET firstname='Demo', lastname='User', company=NULL, telephone=CONCAT('0123-4567', address_id), street=CONCAT('Devstreet ',address_id), email=CONCAT('dev_',address_id,'@trash-mail.com')"

  # orders
  $DBCALL "UPDATE sales_order SET customer_email=CONCAT('dev_',entity_id,'@trash-mail.com'), customer_firstname='Demo', customer_lastname='User', customer_middlename='Dev'"
  $DBCALL "UPDATE sales_order_address SET email=CONCAT('dev_',entity_id,'@trash-mail.com'), firstname='Demo', lastname='User', company=NULL, telephone=CONCAT('0123-4567', entity_id), street=CONCAT('Devstreet ',entity_id)"
  $DBCALL "UPDATE sales_order_grid SET shipping_name='Demo D. User', billing_name='Demo D. User'"

  # payments
  $DBCALL "UPDATE sales_order_payment SET additional_data=NULL, additional_information=NULL"

  # newsletter
  $DBCALL "UPDATE newsletter_subscriber SET subscriber_email=CONCAT('dev_newsletter_',subscriber_id,'@trash-mail.com') WHERE subscriber_email NOT IN ($KEEP_EMAIL)"
else
  ANONYMIZE="n"
fi

#if [[ -z "$TRUNCATE_LOGS" ]]; then
#  echo "  Do you want me to truncate log tables (Y/n)?"; read TRUNCATE_LOGS
#fi
#if [[  "$TRUNCATE_LOGS" == "y" || "$TRUNCATE_LOGS" == "Y" || -z "$TRUNCATE_LOGS" ]]; then
#  TRUNCATE_LOGS="y"
#  # truncate unrequired tables
#  $DBCALL "TRUNCATE log_url"
#  $DBCALL "TRUNCATE log_url_info"
#  $DBCALL "TRUNCATE log_visitor"
#  $DBCALL "TRUNCATE log_visitor_info"
#  $DBCALL "TRUNCATE report_event"
#else
#  TRUNCATE_LOGS="n"
#fi

echo "* Step 2: Mod Config."
# disable assets merging, google analytics and robots
if [[ -z "$DEMO_NOTICE" ]]; then
  echo "  Do you want me to enable demo notice (Y/n)?"; read DEMO_NOTICE
fi
if [[  "$DEMO_NOTICE" == "y" || "$DEMO_NOTICE" == "Y" || -z "$DEMO_NOTICE" ]]; then
  DEMO_NOTICE="y"
  $DBCALL "REPLACE INTO core_config_data (value, path) VALUES ('1', 'design/head/demonotice')"
else
  DEMO_NOTICE="n"
fi
$DBCALL "REPLACE INTO core_config_data (value, path) VALUES ('0', 'dev/css/merge_css_files')"
$DBCALL "REPLACE INTO core_config_data (value, path) VALUES ('0', 'dev/js/merge_files')"
$DBCALL "REPLACE INTO core_config_data (value, path) VALUES ('0', 'google/analytics/active')"
$DBCALL "REPLACE INTO core_config_data (value, path) VALUES ('NOINDEX,NOFOLLOW', 'design/head/default_robots')"

# set mail receivers
$DBCALL "REPLACE INTO  core_config_data (value, path) VALUES ('contact-magento-dev@trash-mail.com', 'trans_email/ident_general/email')"
$DBCALL "REPLACE INTO  core_config_data (value, path) VALUES ('contact-magento-dev@trash-mail.com', 'trans_email/ident_sales/email')"
$DBCALL "REPLACE INTO  core_config_data (value, path) VALUES ('contact-magento-dev@trash-mail.com', 'trans_email/ident_support/email')"
$DBCALL "REPLACE INTO  core_config_data (value, path) VALUES ('contact-magento-dev@trash-mail.com', 'trans_email/ident_custom1/email')"
$DBCALL "REPLACE INTO  core_config_data (value, path) VALUES ('contact-magento-dev@trash-mail.com', 'trans_email/ident_custom2/email')"

# set base urls
if [[ -z "$RESET_BASE_URLS" ]]; then
  echo "  Do you want to reset base urls (Y/n)?"; read RESET_BASE_URLS
fi
if [[ "$RESET_BASE_URLS" == "y" || "$RESET_BASE_URLS" == "Y" || -z "$RESET_BASE_URLS" ]]; then
  RESET_BASE_URLS="y"
  if [[ -z "$SPECIFIC_BASE_URLS" ]]; then
    echo "  Do you want to specify base urls explicitly (Y/n)?"; read SPECIFIC_BASE_URLS
  fi
  if [[ "$SPECIFIC_BASE_URLS" == "y" || "$SPECIFIC_BASE_URLS" == "Y" || -z "$SPECIFIC_BASE_URLS" ]]; then
    SPECIFIC_BASE_URLS="y"
    if [[ -z "$SCOPES" ]]; then
      SCOPES=()
      SCOPE_IDS=()
      BASE_URLS=()

      SCOPE_ID="(to be specified)"
      while [[ "$SCOPE_ID" != "" ]]; do
        echo "Enter scope id [Hit enter to finish]: "
        read SCOPE_ID
        if [[ "$SCOPE_ID" != "" ]]; then
          echo "Enter scope [stores]: "
          read SCOPE
          if [[ "$SCOPE" == "" ]]; then
            SCOPE="stores"
          fi
          echo "Enter base url: "
          read BASE_URL

          SCOPES=("${SCOPES[@]}" $SCOPE)
          SCOPE_IDS=("${SCOPE_IDS[@]}" $SCOPE_ID)
          BASE_URLS=("${BASE_URLS[@]}" $BASE_URL)
        fi
      done
    else
      echo "using preconfigured scope base urls"
    fi

    for i in "${!SCOPES[@]}"; do
      SCOPE=${SCOPES[$i]}
      SCOPE_ID=${SCOPE_IDS[$i]}
      BASE_URL=${BASE_URLS[$i]}
      $DBCALL "UPDATE core_config_data SET value='$BASE_URL' WHERE path IN ('web/unsecure/base_url', 'web/secure/base_url') AND SCOPE_ID=$SCOPE_ID AND SCOPE='$SCOPE'"
      $DBCALL "UPDATE core_config_data SET value='${BASE_URL}media/' WHERE path IN ('web/unsecure/base_media_url', 'web/secure/base_media_url') AND SCOPE_ID=$SCOPE_ID AND SCOPE='$SCOPE'"
      COOKIE_DOMAIN=`echo $BASE_URL|sed -r 's/https?:\/\/([^:\/]*)[\/:].*/\1/g'`
      $DBCALL "UPDATE core_config_data SET value='$COOKIE_DOMAIN' WHERE path = 'web/cookie/cookie_domain' AND SCOPE_ID=$SCOPE_ID AND SCOPE='$SCOPE'"
    done
  else
    SPECIFIC_BASE_URLS="n"
    $DBCALL "UPDATE core_config_data SET value='{{base_url}}' WHERE path='web/unsecure/base_url'"
    $DBCALL "UPDATE core_config_data SET value='{{base_url}}' WHERE path='web/secure/base_url'"
  fi
else
  RESET_BASE_URLS="n"
fi

# increase increment ids
## generate random number from 10 to 100
function genRandomChar() {

  factor=$RANDOM;
  min=65
  max=90
  let "factor %= $max-$min"
  let "factor += $min";

  printf \\$(printf '%03o' $(($factor)))
}

if [[ -z "$RESET_INCREMENT_IDS" ]]; then
  echo "  Do you want me to randomize increment ids (Y/n)?"; read RESET_INCREMENT_IDS
fi
if [[ "$RESET_INCREMENT_IDS" == "y" || "$RESET_INCREMENT_IDS" == "Y" || -z "$RESET_INCREMENT_IDS" ]]; then
PREFIX="`genRandomChar``genRandomChar``genRandomChar`"
$DBCALL "UPDATE eav_entity_store SET increment_last_id=NULL, increment_prefix=CONCAT(store_id, '-', '$PREFIX', '-')"
else
RESET_INCREMENT_IDS='n'
fi



# set test mode everywhere
$DBCALL "UPDATE core_config_data SET value='test' WHERE value LIKE 'live'"
$DBCALL "UPDATE core_config_data SET value='test' WHERE value LIKE 'prod'"
$DBCALL "UPDATE core_config_data SET value=1 WHERE path LIKE '%/testmode'"

# handle PAYONE config
PAYONE_TABLES=`$DBCALL "SHOW TABLES LIKE 'payone_config_payment_method'"`
if [ ! -z "$PAYONE_TABLES" ]; then
  echo "    * Mod PAYONE Config."
  $DBCALL "UPDATE payone_config_payment_method SET mode='test' WHERE mode='live'"
  if [[ -z "$PAYONE_MID" && -z "$PAYONE_PORTALID" && -z "$PAYONE_AID" && -z "$PAYONE_KEY" ]]; then
    echo -e "\E[1;31mCaution: \E[0mYou probably need to change portal IDs and keys for your staging/dev PAYONE payment methods!"
    echo "Please enter your testing/staging/dev merchant ID: "
    read PAYONE_MID
    echo "Please enter your testing/staging/dev portal ID: "
    read PAYONE_PORTALID
    echo "Please enter your testing/staging/dev sub account ID: "
    read PAYONE_AID
    echo "Please enter your testing/staging/dev security key: "
    read PAYONE_KEY
  fi

  $DBCALL "UPDATE core_config_data SET value='$PAYONE_MID' WHERE path='payone_general/global/mid'"
  $DBCALL "UPDATE core_config_data SET value='$PAYONE_PORTALID' WHERE path='payone_general/global/portalid'"
  $DBCALL "UPDATE core_config_data SET value='$PAYONE_AID' WHERE path='payone_general/global/aid'"
  $DBCALL "UPDATE core_config_data SET value='$PAYONE_KEY' WHERE path='payone_general/global/key'"

  $DBCALL "UPDATE payone_config_payment_method SET mid='$PAYONE_MID' WHERE mid IS NOT NULL"
  $DBCALL "UPDATE payone_config_payment_method SET portalid='$PAYONE_PORTALID' WHERE portalid IS NOT NULL"
  $DBCALL "UPDATE payone_config_payment_method SET aid='$PAYONE_AID' WHERE aid IS NOT NULL"
  $DBCALL "UPDATE payone_config_payment_method SET \`key\`='$PAYONE_KEY' WHERE \`key\` IS NOT NULL"
fi

echo "Done."

if [[ ! -f $CONFIG ]]; then
  echo "Do you want to create an anonymizer configuration file based on your answers (Y/n)?"; read CREATE
  if [[  "$CREATE" == "y" || "$CREATE" == "Y" || -z "$CREATE" ]]; then
    echo "DEV_IDENTIFIERS=$DEV_IDENTIFIERS">>$CONFIG
    echo "RESET_ADMIN_PASSWORDS=$RESET_ADMIN_PASSWORDS">>$CONFIG
    echo "RESET_API_PASSWORDS=$RESET_API_PASSWORDS">>$CONFIG
    echo "KEEP_EMAIL=$KEEP_EMAIL">>$CONFIG
    echo "ANONYMIZE=$ANONYMIZE">>$CONFIG
    echo "TRUNCATE_LOGS=$TRUNCATE_LOGS">>$CONFIG
    echo "DEMO_NOTICE=$DEMO_NOTICE">>$CONFIG
    if [ ! -z "$PAYONE_TABLES" ]; then
      echo "PAYONE_MID=$PAYONE_MID">>$CONFIG
      echo "PAYONE_PORTALID=$PAYONE_PORTALID">>$CONFIG
      echo "PAYONE_AID=$PAYONE_AID">>$CONFIG
      echo "PAYONE_KEY=$PAYONE_KEY">>$CONFIG
    fi
    echo "RESET_BASE_URLS=$RESET_BASE_URLS">>$CONFIG
    echo "RESET_INCREMENT_IDS=$RESET_INCREMENT_IDS">>$CONFIG
    echo "SPECIFIC_BASE_URLS=$SPECIFIC_BASE_URLS">>$CONFIG
    if [[ ! -z $SCOPES ]]; then
      echo "SCOPES=(${SCOPES[@]})">>$CONFIG
      echo "SCOPE_IDS=(${SCOPE_IDS[@]})">>$CONFIG
      echo "BASE_URLS=(${BASE_URLS[@]})">>$CONFIG
    fi
  fi
fi
