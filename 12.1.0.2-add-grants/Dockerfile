FROM datagrip/oracle:12.1.0.2-se2-directio

ADD create-test-users.sql /opt/oracle/create-test-users.sql
COPY runOracle1.sh /opt/oracle/runOracle1.sh

USER root

RUN chmod 755 /opt/oracle/runOracle1.sh && chown oracle:oinstall /opt/oracle/runOracle1.sh
ENV RUN_FILE=runOracle1.sh

USER oracle

