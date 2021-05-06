# Analyze Hurricane Dorian Twitter data, by Joseph Holler, 2019
# following tutorial at:
# https://www.earthdatascience.org/courses/earth-analytics/get-data-using-apis/use-twitter-api-r/
# also get advice from the rtweet page: https://rtweet.info/

#install packages for twitter, census, data management, and mapping
packages = c("rtweet","tidycensus","tidytext","maps","RPostgres","igraph","tm", 
             "ggplot2","RColorBrewer","rccmisc","ggraph","here")
setdiff(packages, rownames(installed.packages()))
install.packages(setdiff(packages, 
                         rownames(installed.packages())), quietly=TRUE)

#initialize the libraries. this must be done each time you load the project
library(rtweet)
library(igraph)
library(dplyr)
library(tidytext)
library(tm)
library(tidyr)
library(ggraph)
library(tidycensus)
library(ggplot2)
library(RPostgres)
library(RColorBrewer)
library(DBI)
library(rccmisc)
library(here)

########## load data from local file ########
tornado = readRDS(here("data","derived","private","tornado.RDS"))
baseline = readRDS(here("data","derived","private","baseline.RDS"))


############# TEMPORAL ANALYSIS ############# 

#create temporal data frame & graph it
# interesting! biggest spike is on april 29, well before the time indicated by NYT article (Monday, 5/3)
tornadoTweetsByHour <- ts_data(tornado, by="hours")
ts_plot(tornado, by="hours")


############# NETWORK ANALYSIS ############# 

# Create network data frame. 
# Other options for 'edges' in the network include mention, retweet, and reply
# modify this to graph retweets, like the california wildfire paper? 
# can't, bc we excluded retweets - but might get something interesting from revising this graph of quotes
tornadoNetwork <- network_graph(tornado, c("quote"))
plot.igraph(tornadoNetwork)
# This graph needs serious work... e.g. subset to a single state maybe?


############# TEXT / CONTEXTUAL ANALYSIS ############# 

# remove urls, fancy formatting, etc. in other words, clean the text content
tornadoText = tornado %>% select(text) %>% plain_tweets()

# parse out words from tweet text
tornadoWords = tornadoText %>% unnest_tokens(word, text)

# how many words do you have including the stop words?
count(tornadoWords)

# create list of stop words (useless words not worth analyzing) 
data("stop_words")

# add "t.co" twitter links to the list of stop words
# also add the twitter search terms to the list
# change these added stop words to include my new search terms
stop_words = stop_words %>% 
  add_row(word="t.co",lexicon = "SMART") %>% 
  add_row(word="hail",lexicon = "Search") %>% 
  add_row(word="tornado",lexicon = "Search") %>% 
  add_row(word="storm",lexicon = "Search")

#delete stop words from tornadoWords with an anti_join
tornadoWords =  tornadoWords %>% anti_join(stop_words) 

# how many words after removing the stop words?
count(tornadoWords)

# graph frequencies of words
tornadoWords %>%
  count(word, sort = TRUE) %>%
  top_n(15) %>%
  mutate(word = reorder(word, n)) %>%
  ggplot(aes(x = word, y = n)) +
  geom_col() +
  xlab(NULL) +
  coord_flip() +
  labs(x = "Count",
       y = "Unique words",
       title = "Count of unique words found in tweets")

# separate words and count frequency of word pair occurrence in tweets
# "cdt" and "pm" are top words both individually and together - might reflect many tweets automatically produced from 
# government or weather service updates
tornadoWordPairs = tornadoText %>% 
  mutate(text = removeWords(tolower(text), stop_words$word)) %>%
  unnest_tokens(paired_words, text, token = "ngrams", n = 2) %>%
  separate(paired_words, c("word1", "word2"),sep=" ") %>%
  count(word1, word2, sort=TRUE)

# graph a word cloud with space indicating association.
# you may change the filter to filter more or less than pairs with 30 instances
# numbers indicating time are also frequent - should I filter these out?
# this kinda makes the case for filtering out weather update tweets stronger, although it could be interesting to
# do some analysis of hoe much influence these tweets have
tornadoWordPairs %>%
  filter(n >= 25 & !is.na(word1) & !is.na(word2)) %>%
  graph_from_data_frame() %>%
  ggraph(layout = "fr") +
  geom_edge_link(aes(edge_alpha = n, edge_width = n)) +
  geom_node_point(color = "darkslategray4", size = 3) +
  geom_node_text(aes(label = name), vjust = 1.8, size = 3) +
  labs(title = "Word Network of Tweets during Tornado Warnings",
       x = "", y = "") +
  theme_void()


############# SPATIAL ANALYSIS ############# 

#first, sign up for a Census API here:
# https://api.census.gov/data/key_signup.html
#replace the key text 'yourkey' with your own key!
counties <- get_estimates("county",
                          product="population",
                          output="wide",
                          geometry=TRUE, keep_geo_vars=TRUE, 
                          key="96d81b8f2a75a110e7cba6be5260c280ea06ec1b")

# select only the states you want, with FIPS state codes
# look up fips codes here:
# https://en.wikipedia.org/wiki/Federal_Information_Processing_Standard_state_code 
# change state filters for my tornado analysis
counties = filter(counties,
                  STATEFP %in% c('01', '05', '10', '11', '12', '13', '17', '18', '19', '20',
                                 '21', '22', '24', '26', '27', '28', '29', '31', '34', '37',
                                 '38', '39', '40', '42', '45', '46', '47', '48', '51', '54', '55'))

# save counties to Derived/Public folder
saveRDS(counties, here("data","derived","public","counties.RDS"))

# map results with GGPlot
# note: cut_interval is an equal interval classification function, while 
# cut_number is a quantile / equal count function
# you can change the colors, titles, and transparency of points
ggplot() +
  geom_sf(data=counties, aes(fill=cut_number(DENSITY,5)), color="grey")+
  scale_fill_brewer(palette="GnBu")+
  guides(fill=guide_legend(title="Population Density"))+
  geom_point(data = tornado, aes(x=lng,y=lat),
             colour = 'purple', alpha = .2) +
  labs(title = "Tweet Locations During Tornado Event")+
  theme(plot.title=element_text(hjust=0.5),
        axis.title.x=element_blank(),
        axis.title.y=element_blank())


############### UPLOAD RESULTS TO POSTGIS DATABASE ###############

# Connecting to Postgres
# Create a con database connection with the dbConnect function.
# Change the user and password to your own!
con <- dbConnect(RPostgres::Postgres(), 
                 dbname='dsm', 
                 host='artemis', 
                 user='user', 
                 password='password') 

#list the database tables, to check if the database is working
dbListTables(con) 

#create a simple table for uploading
doriansql <- select(dorian,c("user_id","status_id","text","lat","lng"),
                    starts_with("place"))

#write data to the database
dbWriteTable(con,'dorian',doriansql, overwrite=TRUE)

# try also writing the november tweet data to the database! Add code below:

# write counties table with lower-case column names to the database
dbWriteTable(con,'counties',lownames(counties), overwrite=TRUE)


############### SPATIAL JOIN AND MAPPING NORMALIZED TWEETS ###############

# Either in R or in PostGIS (via QGIS DB Manager)...

# Count the number of dorian points in each county
# Count the number of november points in each county
# Set counties with no points to 0 for the november count
# Calculate the normalized difference tweet index (made this up, based on NDVI), 
# where ndti = (tweets about storm – baseline twitter activity) / 
#              (tweets about storm + baseline twitter activity)
# remember to multiply something by 1.0 so that you'll get decimal division
# also if the denominator would end up being 0, set the result to 0

# See 03-spatial-join.sql for tips on managing the data in PostGIS

# Either in QGIS or in R...
# Map the normalized tweet difference index for Hurricane Dorian
# Try using the heatmap symbology in QGIS to visualize kernel density of tweets


############### SAVE RESULTS FROM POSTGIS SPATIAL JOIN ###############

# pull results back from the database, replacing 'tablename' with the name
# of table with results at county level
county_tweets = dbReadTable(con, "tablename")

# save county-level results to derived/public
saveRDS(county_tweets, here("data","derived","public","county_tweets.RDS"))

#disconnect from the database
dbDisconnect(con)
