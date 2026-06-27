# CAT 3.0.1 + mysql-connector-java 5.1.49
#
# 官方镜像 meituaninc/cat:3.0.1 内置 mysql-connector-java 5.1.20，
# 与 MySQL 8 不兼容（不识别 serverTimezone/allowPublicKeyRetrieval 等参数，
# c3p0 报 CannotAcquireResourceException，真因被吞）。
#
# 不能直接换 8.x driver：8.x 之 ResultSet.getObject 对 DATETIME 列返
# java.time.LocalDateTime，而 CAT 之 unidal DAL 反射塞进 java.util.Date 字段，
# 类型不匹配，配置表读取全挂。
#
# 5.1.49（2020 最后 5.1 版）是甜蜜点：
#   - 支持 MySQL 8 之 mysql_native_password / useSSL / serverTimezone
#   - DATETIME 仍返 java.sql.Timestamp（继承 java.util.Date），unidal 兼容
#
# 构建：
#   docker compose -f cat.yml build cat
# 同目录需有：
#   - mysql-connector-java-5.1.49.jar
#     curl -L -o mysql-connector-java-5.1.49.jar \
#       https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.49/mysql-connector-java-5.1.49.jar

FROM meituaninc/cat:3.0.1
USER root

# 镜像基于 alpine（musl libc），用 apk 装 unzip
RUN apk add --no-cache unzip

# 预解压 cat.war，删 5.1.20 旧 driver，删 war 防 Tomcat 重新部署覆盖
RUN cd /usr/local/tomcat/webapps && \
    mkdir -p cat && cd cat && \
    unzip -oq ../cat.war && \
    rm -f WEB-INF/lib/mysql-connector-java-5.1.20.jar && \
    rm /usr/local/tomcat/webapps/cat.war

# 灌入 5.1.49 driver
COPY mysql-connector-java-5.1.49.jar /usr/local/tomcat/webapps/cat/WEB-INF/lib/
