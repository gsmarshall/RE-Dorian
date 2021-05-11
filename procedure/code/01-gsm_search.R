# search geographic twitter data for Hurricane Dorian
# by Joseph Holler, 2019,2021
# This code requires a twitter developer API token!
# See https://cran.r-project.org/web/packages/rtweet/vignettes/auth.html

# install packages for twitter querying and initialize the library
packages = c("rtweet","here","dplyr","rehydratoR")
setdiff(packages, rownames(installed.packages()))
install.packages(setdiff(packages, rownames(installed.packages())),
                 quietly=TRUE)

library(rtweet)
library(here)
library(dplyr)
library(rehydratoR)

############# SEARCH TWITTER API ############# 

# reference for search_tweets function: 
# https://rtweet.info/reference/search_tweets.html 
# don't add any spaces in between variable name and value for your search
# e.g. n=1000 is better than n = 1000
# the first parameter in quotes is the search string
# n=10000 asks for 10,000 tweets
# if you want more than 18,000 tweets, change retryonratelimit to TRUE and 
# wait 15 minutes for every batch of 18,000
# include_rts=FALSE excludes retweets.
# token refers to the twitter token you defined above for access to your twitter
# developer account
# geocode is equal to a string with three parts: longitude, latitude, and 
# distance with the units mi for miles or km for kilometers

# set up twitter API information with your own information for
# app, consumer_key, and consumer_secret
# this should launch a web browser and ask you to log in to twitter
# for authentication of access_token and access_secret
twitter_token = create_token(
  app = "MyApp",                     #enter your app name in quotes
  consumer_key = "mykey",  		      #enter your consumer key in quotes
  consumer_secret = "mysecret",         #enter your consumer secret in quotes
  access_token = "mytoken",
  access_secret = "myaccess"
)

# get tweets for tornadoes in the southeast
# point is southwestern Tennessee - according to NYtimes article, tornado activity and damage was
# reported in georgia, kentucky, mississippi, south carolina, with warnings/watches in pretty much all surrounding states
tornado = search_tweets("tornado OR hail OR storm",
                       n=200000, include_rts=FALSE,
                       token=twitter_token, 
                       geocode="34,-87,1000km",
                       retryonratelimit=TRUE) 


# get tweets without any text filter for the same geographic region in November, 
# searched on May 4, 2021
# this code will no longer work! It is here for reference.
# the query searches for all verified or unverified tweets, i.e. everything
baseline = search_tweets("-filter:verified OR filter:verified", 
                         n=200000, include_rts=FALSE, 
                         token=twitter_token,
                         geocode="34,-87,1000km", 
                         retryonratelimit=TRUE)

############# LOAD SEARCH TWEET RESULTS  ############# 

### REVAMP THESE INSTRUCTIONS

# load tweet status id's for Hurricane Dorian search results
dorianids = 
  data.frame(read.table(here("data","raw","public","dorianids.txt"), 
                        numerals = 'no.loss'))

# load cleaned status id's for November general twitter search
novemberids =
  data.frame(read.table(here("data","derived","public","novemberids.txt"),
                        numerals = 'no.loss'))

# rehydrate dorian tweets
dorian_raw = rehydratoR(twitter_token$app$key, twitter_token$app$secret, 
                twitter_token$credentials$oauth_token, 
                twitter_token$credentials$oauth_secret, dorianids, 
                base_path = NULL, group_start = 1)

# alternatively, geog 323 students may load original dorian tweets
# download dorian_raw.RDS from 
# https://github.com/GIS4DEV/geog323data/raw/main/dorian/dorian_raw.RDS
# and save to the data/raw/private folder
dorian_raw = readRDS(here("data","raw","private","dorian_raw.RDS"))

# rehydrate november tweets
november = rehydratoR(twitter_token$app$key, twitter_token$app$secret, 
                        twitter_token$credentials$oauth_token, 
                        twitter_token$credentials$oauth_secret, novemberids, 
                        base_path = NULL, group_start = 1)

# alternatively, geog 323 students may load 13228 cleaned november tweets
# download november.RDS from 
# https://github.com/GIS4DEV/geog323data/raw/main/dorian/november.RDS
# and save to the data/derived/private folder
november = readRDS(here("data","derived","private","november.RDS"))

############# FILTER DORIAN FOR CREATING PRECISE GEOMETRIES ############# 

# reference for lat_lng function: https://rtweet.info/reference/lat_lng.html
# adds a lat and long field to the data frame, picked out of the fields
# that you indicate in the c() list
# sample function: lat_lng(x, coords = c("coords_coords", "bbox_coords"))

# list and count unique place types
# NA results included based on profile locations, not geotagging / geocoding.
# If you have these, it indicates that you exhausted the more precise tweets 
# in your search parameters and are including locations based on user profiles
count(tornado, place_type)

# convert GPS coordinates into lat and lng columns
# do not use geo_coords! Lat/Lng will be inverted
tornado_loc = lat_lng(tornado, coords=c("coords_coords"))
baseline_loc = lat_lng(baseline, coords=c("coords_coords"))

# select any tweets with lat and lng columns (from GPS) or 
# designated place types of your choosing
tornado_loc = subset(tornado_loc, 
                place_type == 'city'| place_type == 'neighborhood'| 
                  place_type == 'poi' | !is.na(lat))

baseline_loc = subset(baseline_loc,
                  place_type == 'city'| place_type == 'neighborhood'| 
                    place_type == 'poi' | !is.na(lat))

# convert bounding boxes into centroids for lat and lng columns
tornado_loc = lat_lng(tornado_loc,coords=c("bbox_coords"))
baseline_loc = lat_lng(baseline_loc,coords=c("bbox_coords"))

# re-check counts of place types
count(tornado_loc, place_type)

############# SAVE FILTERED TWEET IDS TO DATA/DERIVED/PUBLIC ############# 

write.table(tornado_loc$status_id,
            here("data","derived","public","tornadoids.txt"), 
            append=FALSE, quote=FALSE, row.names = FALSE, col.names = FALSE)

write.table(baseline_loc$status_id,
            here("data","derived","public","baselineids.txt"), 
            append=FALSE, quote=FALSE, row.names = FALSE, col.names = FALSE)

############# SAVE TWEETs TO DATA/DERIVED/PRIVATE ############# 

saveRDS(tornado_loc, here("data","derived","private","tornado.RDS"))
saveRDS(baseline_loc, here("data","derived","private","baseline.RDS"))

# save raw data just in case
saveRDS(tornado, here("data","derived","private","tornado_raw.RDS"))
saveRDS(baseline, here("data","derived","private","baseline_raw.RDS"))
