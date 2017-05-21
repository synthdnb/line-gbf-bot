# Usage  
`docker run -d -p7458:4567 --link gbf-redis:redis -e LINE_CHANNEL_TOKEN=$LINE_CHANNEL_TOKEN -e LINE_CHANNEL_SECRET=$LINE_CHANNEL_SECRET --name gbf-line-bot synthdnb/gbf-line-bot`