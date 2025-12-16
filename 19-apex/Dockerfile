FROM datagrip/oracle:19.3-e

USER root

ADD https://download.oracle.com/otn_software/apex/apex_24.2_en.zip /tmp
# or download from https://drive.google.com/drive/folders/1b_4y0zT8zl4zYkNWkyDict1LH5m-g995?usp=drive_link

RUN yum install -y unzip

RUN unzip /tmp/apex_24.2_en.zip
RUN chown -R oracle:dba /home/oracle

USER oracle
