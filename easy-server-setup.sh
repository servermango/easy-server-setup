#!/bin/bash

# ASCII Art with copyright message
ascii_art="                                                                             
                                                                                          
                           -=-                 ........:::::::::::::::.                  
                           -=:              ....::::::::::::::::::::::::.                
                   .:-==-::==                      .::::::::::::::::::....             
                 :======++++=         .                .::::::::::::::::.....           
              .-=++++++++*===  ..............            ::::::::::::::.......         
          .:-=++++++++=-.   .::.................          .:::::::::::::......         
                          ::::::::................          :::::::::::::::::          
                        ::::::::::::................         ::::::::::::::::          
                       :---:::::::::::::..............        .:::::::::::::::          
                      :-------::::::::::::..............       :::::::::::::::          
                    ---------------------------::::::::.    :----------------          
                    -----------------------------:::::::     ------------------          
                    .-------------------------------:::    .------------:-----:          
               :-    ---------------------------------    .-------------------:          
               --:    -=====--------------------------    :--------------=====:          
              .---.    -==========--------------------:    :-------------=====:          
              :====:    -===============----------------.    :-----------=====:              
             :=========:     :-=========================-:    :====-----======.          
            .==============:       .:--=========--::.       .-========-=======.          
             .-==============-:                         .::===================           
                .-===============-:..             ..::-===============-========             
                        .::-===========================================-:.               
                              .::--=================================:..                   
                                     ...:---===================-::                        
                                                 ..........                               
                 
\nCopyright 2024 ServerMango. For help and support or to hire us mail us on helpdesk@servermango.com\n"

# Default PHP version
php_version="8.1"

# Function to display ASCII art
display_ascii_art() {
    echo -e "$ascii_art"
}

# Function to install Apache if not installed
install_apache() {
    echo "Installing Apache..."
    sudo apt update
    sudo apt install apache2 -y
    sudo a2enmod rewrite
    sudo a2enmod ssl
    sudo systemctl restart apache2
}

# Function to install PHP if not installed
install_php() {
    echo "Installing PHP $php_version..."
    sudo apt update
    sudo apt install php$php_version libapache2-mod-php$php_version -y
    sudo systemctl restart apache2
}

# Function to install MySQL if not installed
install_mysql() {
    echo "Installing MySQL..."
    sudo apt update
    sudo apt install mysql-server -y
    sudo systemctl start mysql
    sudo systemctl enable mysql
}

# Function to check if OpenSSL is installed, if not, install it
check_and_install_openssl() {
    if ! command -v openssl &> /dev/null
    then
        echo "Installing OpenSSL..."
        sudo apt update
        sudo apt install openssl -y
    else
        echo "OpenSSL is already installed."
    fi
}

# Function to check if Certbot is installed, if not, install it
check_and_install_certbot() {
    if ! command -v certbot &> /dev/null
    then
        echo "Installing Let's Encrypt (certbot)..."
        sudo apt update
        sudo apt install certbot python3-certbot-apache -y
    else
        echo "Certbot is already installed."
    fi
}

# Function to install phpMyAdmin if not installed
install_phpmyadmin() {
    echo "Installing phpMyAdmin..."

    # Generate a random and strong password
    phpmyadmin_password=$(openssl rand -base64 24)

    sudo apt update
    sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/dbconfig-install boolean true"
    sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/app-password-confirm password '$phpmyadmin_password'"
    sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/admin-pass password '$phpmyadmin_password'"
    sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/app-pass password '$phpmyadmin_password'"
    sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2"
    sudo apt install phpmyadmin -y

    # Create symbolic link for /phpmyadmin
    sudo ln -s /usr/share/phpmyadmin /var/www/html/phpmyadmin

    # Display the generated password
    echo "phpMyAdmin has been installed. The MySQL root password is: $phpmyadmin_password"
}

# Function to hide the phpMyAdmin symbolic link for a specific domain
hide_phpmyadmin() {

    pma_link="/var/www/html/phpmyadmin"

    if [ -L "$pma_link" ]; then
        echo "Removing phpMyAdmin symbolic link "
        sudo rm "$pma_link"
        echo "phpMyAdmin symbolic link removed  "
        disable_phpmyadmin_config  # Disable the configuration
    else
        echo "phpMyAdmin symbolic link does not exist "
    fi

    echo "Removing global phpMyAdmin configuration..."
    
    # Disable the phpMyAdmin Apache configuration
    sudo a2disconf phpmyadmin

    # Reload Apache to apply the changes
    sudo systemctl reload apache2

}


# Function to re-add the phpMyAdmin symbolic link for a specific domain
show_phpmyadmin() {

    echo "Re-adding global phpMyAdmin configuration..."
    
    # Enable the phpMyAdmin Apache configuration
    sudo a2enconf phpmyadmin

    # Reload Apache to apply the changes
    sudo systemctl reload apache2

    echo "Global phpMyAdmin configuration re-added and Apache reloaded."

    pma_link="/var/www/html/phpmyadmin"

    if [ ! -L "$pma_link" ]; then
        echo "Re-adding global phpMyAdmin symbolic link..."
        sudo ln -s /usr/share/phpmyadmin "$pma_link"
        echo "Global phpMyAdmin symbolic link added."
    else
        echo "phpMyAdmin symbolic link already exists."
    fi
    
}


# Function to create a MySQL user with all privileges
create_mysql_user() {
    
    password=$(openssl rand -base64 24)  # Generate a strong password

    echo "Creating MySQL user dbuser with full privileges..."
    sudo mysql -e "CREATE USER 'dbuser'@'localhost' IDENTIFIED BY '$password';"
    sudo mysql -e "ALTER USER 'dbuser'@'localhost' IDENTIFIED WITH mysql_native_password BY '$password';"
    sudo mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'dbuser'@'localhost' WITH GRANT OPTION;"
    sudo mysql -e "FLUSH PRIVILEGES;"

    echo "MySQL user dbuser created with the following password: $password"
}

# Function to install unzip if not installed
install_unzip() {
    if ! command -v unzip &> /dev/null
    then
        echo "Installing unzip..."
        sudo apt update
        sudo apt install unzip -y
    fi
}

# Function to download and extract the latest version of WordPress
download_wp() {
    domain=$1
    public_html="/var/www/$domain/public_html"

    # Install unzip if not installed
    install_unzip

    # Download the latest version of WordPress
    wget https://wordpress.org/latest.zip -P /tmp

    # Extract WordPress to the public_html directory
    unzip /tmp/latest.zip -d /tmp
    sudo mv /tmp/wordpress/* $public_html
    sudo chown -R $USER:$USER $public_html

    # Clean up
    rm -rf /tmp/wordpress /tmp/latest.zip

    echo "Downloaded and extracted the latest version of WordPress for $domain"
}

# Function to create Apache virtual host configuration
create_vhost() {
    domain=$1
    public_html="/var/www/$domain/public_html"
    conf_file="/etc/apache2/sites-available/$domain.conf"

    # Create directory if it doesn't exist
    if [ ! -d "$public_html" ]; then
        sudo mkdir -p $public_html
        sudo chown -R $USER:$USER $public_html
    fi

    # Create virtual host configuration (HTTP only)
    echo "<VirtualHost *:80>
    ServerName $domain
    DocumentRoot $public_html

    <Directory $public_html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${domain}_error.log
    CustomLog \${APACHE_LOG_DIR}/${domain}_access.log combined
</VirtualHost>" | sudo tee $conf_file

    # Enable the site
    sudo a2ensite $domain.conf

    # Reload Apache
    sudo systemctl reload apache2

    echo "Created Apache config for $domain"
}

# Function to add SSL configuration to the virtual host
add_ssl_to_vhost() {
    domain=$1
    conf_file="/etc/apache2/sites-available/$domain.conf"

    # Append SSL configuration to the existing virtual host configuration
    echo "<VirtualHost *:443>
    ServerName $domain
    DocumentRoot /var/www/$domain/public_html

    <Directory /var/www/$domain/public_html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/$domain/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$domain/privkey.pem
    Include /etc/letsencrypt/options-ssl-apache.conf

    ErrorLog \${APACHE_LOG_DIR}/${domain}_error_ssl.log
    CustomLog \${APACHE_LOG_DIR}/${domain}_access_ssl.log combined
</VirtualHost>" | sudo tee -a $conf_file

    # Reload Apache
    sudo systemctl reload apache2

    echo "Added SSL configuration for $domain"
}

# Function to install SSL certificate using Let's Encrypt
install_ssl() {
    domain=$1

    # Install SSL certificate using certbot
    sudo certbot --apache --force-renewal -d $domain --non-interactive --agree-tos --email sales@iqltech.com

    echo "Installed SSL for $domain"
}

# Function to remove domain configuration and SSL certificates
remove_domain() {
    domain=$1
    conf_file="/etc/apache2/sites-available/$domain.conf"
    conf_file2="/etc/apache2/sites-enabled/$domain.conf"
    
    # Disable the site
    sudo a2dissite $domain.conf

    # remove enabled site config
    sudo rm -f $conf_file2
    
    # Remove the configuration file
    sudo rm -f $conf_file

    # Remove SSL certificate using certbot
    sudo certbot delete --cert-name $domain

    # Reload Apache
    sudo systemctl reload apache2
    
    sudo systemctl restart apache2

    echo "Removed Apache config and SSL for $domain"
}

# Function to enable UFW firewall and allow Apache ports 80 and 443
configure_firewall() {
    echo "Configuring UFW firewall..."

    # Enable UFW if it's not enabled
    sudo ufw enable

    # Allow Apache Full profile (80 and 443 ports)
    sudo ufw allow 'Apache Full'

    # Reload UFW
    sudo ufw reload

    echo "UFW firewall configured to allow Apache ports 80 and 443."
}

# Function to install basic software if the --install-basics flag is used
install_basics() {
    # Check if Apache is installed, if not, install it
    if ! command -v apache2 &> /dev/null
    then
        install_apache
    fi

    # Check if PHP is installed, if not, install it
    if ! command -v php &> /dev/null || ! php -v | grep -q $php_version
    then
        install_php
    fi

    # Check if MySQL is installed, if not, install it
    if ! command -v mysql &> /dev/null
    then
        install_mysql
    fi

    # Check and install OpenSSL
    check_and_install_openssl

    # Check and install Certbot (Let's Encrypt)
    check_and_install_certbot

    # Install phpMyAdmin if not installed
    if ! [ -d /usr/share/phpmyadmin ]; then
        install_phpmyadmin
    fi

    # Configure firewall (UFW) to allow Apache 80 and 443
    configure_firewall
}

# Display ASCII art with the copyright message
display_ascii_art

# Parse command-line arguments
install_basics_flag=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --install-basics)
            install_basics_flag=true
            shift
            ;;
        --php-version)
            php_version="$2"
            shift
            ;;
        --create|--remove|--download-wp)
            command=$1
            domains=()
            shift
            while [[ "$#" -gt 0 && "$1" != --* ]]; do
                domains+=("$1")
                shift
            done
            ;;
        --hide-pma)
            domain=$2
            hide_phpmyadmin
            shift 2
            ;;
        --show-pma)
            domain=$2
            show_phpmyadmin $domain
            shift 2
            ;;
        --install-ssl)
            ssl_domain=$2
            install_ssl $ssl_domain
            add_ssl_to_vhost $ssl_domain
            shift 2
            ;;
        *)
            echo "Invalid option: $1"
            exit 1
            ;;
    esac
done


# Execute installation if --install-basics was passed
if [ "$install_basics_flag" = true ]; then
    install_basics
fi

# Execute the appropriate command for the domains
for domain in "${domains[@]}"; do
    if [ "$command" == "--create" ]; then
        create_vhost $domain
        create_mysql_user "phpmyadmin_$domain"
        install_ssl $domain
        add_ssl_to_vhost $domain
    elif [ "$command" == "--remove" ]; then
        remove_domain $domain
    elif [ "$command" == "--download-wp" ]; then
        download_wp $domain
    else
        echo "Invalid command."
        exit 1
    fi
done
