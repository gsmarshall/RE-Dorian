-- SQL queries from dorian tweet lab 4/28
alter table dorian
add column dorian_tweets int;

update counties
set dorian_tweets = tweets from -- need to select a column from the result of the subquery insteadof just giving it the whole 'select' statement
(select countyfp, count(user_id) as tweets from
counties inner join dorian
on st_intersects(counties.geom, dorian.geom)
group by countyfp) as a
where counties.countyfp = a.countyfp;  -- where clause links results back to specific rows in the counties table

alter table counties
add column november_tweets int;

-- calculate baseline tweets per county and change null values to 0
update counties
set november_tweets = tweets from
(select countyfp, case when count(user_id) > 0 then count(user_id) else 0 end as tweets
from counties inner join november_new
on st_intersects(counties.geom, november_new.geom)
group by countyfp) as a
where counties.countyfp = a.countyfp

-- set null values to 0
update counties
set november_tweets =
case when november_tweets is null then 0 else november_tweets end
