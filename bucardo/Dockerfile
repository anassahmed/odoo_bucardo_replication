FROM anassahmed/postgres:9.4
MAINTAINER Anass Ahmed <anass.1430@gmail.com>

RUN apt update && apt install -y bucardo

COPY start.sh /

ENTRYPOINT ["./start.sh"]
