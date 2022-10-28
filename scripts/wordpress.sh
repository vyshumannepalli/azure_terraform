
#!/bin/bash
# install httpd
sudo apt update -y
sudo apt -y install httpd
sudo apt -y install php php-mysql php-fpm php-gd

sudo systemctl enable httpd
sudo systemctl start httpd
# install mysql client
sudo yum -y install apache2

sudo cd /var/www/html
  echo "<?php echo 'Hello World!!'?>" > index.php  


