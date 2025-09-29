-- Databricks notebook source
-- MAGIC %md
-- MAGIC
-- MAGIC
-- MAGIC # Delta Lake Foundamentals
-- MAGIC ## Learning Objectives
-- MAGIC By the end of this lesson, you should be able to:
-- MAGIC * Describe the directory structure of Delta Lake files
-- MAGIC * Review a history of table transactions
-- MAGIC * Query and roll back to previous table version
-- MAGIC * Use **`OPTIMIZE`** to compact small files

-- COMMAND ----------

-- MAGIC %md
-- MAGIC We start creating a simple table about **students** that we will use as a reference to understand better Lakehouse concepts

-- COMMAND ----------

CREATE TABLE students 
  (id INT, name STRING, value DOUBLE)
  TBLPROPERTIES (delta.enableChangeDataFeed = true)
  LOCATION 's3://club-data-lakehouse-bucket/Datalakehouse/MDT/students';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC We insert some values into the table, such as an id, a name and a value

-- COMMAND ----------

INSERT INTO students VALUES (1, "Yve", 1.0);
INSERT INTO students VALUES (2, "Omar", 2.5);
INSERT INTO students VALUES (3, "Elia", 3.3);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC We continue to insert values into the table

-- COMMAND ----------

INSERT INTO students
VALUES 
  (4, "Ted", 4.7),
  (5, "Tiffany", 5.5),
  (6, "Vini", 6.3);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC We update all the values for all the students with name that start with T letter. Ted and Tiffany are affected by the updates

-- COMMAND ----------

UPDATE students 
SET value = value + 1
WHERE name LIKE "T%";

-- COMMAND ----------

-- MAGIC %md
-- MAGIC We then delete all students that have a value > 6. Tiffany and Vini record are deleted.

-- COMMAND ----------

DELETE FROM students 
WHERE value > 6;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC To simulate a bulk update of the table through a **MERGE** operation, we create a temporary view with all the modification that we want to process to the table

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW updates(id, name, value, type) AS VALUES
  (2, "Omar", 15.2, "update"),
  (3, "", null, "delete"),
  (7, "Blue", 7.7, "insert"),
  (11, "Diya", 8.8, "update");

-- COMMAND ----------

select * from updates;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Lastly, we apply the MERGE operation to the table. MERGE will do the following:
-- MAGIC - Update repord 2 and record 11
-- MAGIC - Delete the record 3
-- MAGIC - Insert the new record 7

-- COMMAND ----------

MERGE INTO students b
USING updates u
ON b.id=u.id
WHEN MATCHED AND u.type = "update"
  THEN UPDATE SET *
WHEN MATCHED AND u.type = "delete"
  THEN DELETE
WHEN NOT MATCHED AND u.type = "insert"
  THEN INSERT *;

-- COMMAND ----------

select * from students;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC
-- MAGIC
-- MAGIC ## Examine Table Details
-- MAGIC
-- MAGIC Databricks uses a Hive metastore by default to register schemas, tables, and views.
-- MAGIC
-- MAGIC Using **`DESCRIBE EXTENDED`** allows us to see important metadata about our table.

-- COMMAND ----------

DESCRIBE EXTENDED students

-- COMMAND ----------

-- MAGIC %md
-- MAGIC
-- MAGIC
-- MAGIC **`DESCRIBE DETAIL`** is another command that allows us to explore table metadata.

-- COMMAND ----------

DESCRIBE DETAIL students

-- COMMAND ----------

-- MAGIC %md
-- MAGIC
-- MAGIC
-- MAGIC Note the **`Location`** field.
-- MAGIC
-- MAGIC While we've so far been thinking about our table as just a relational entity within a schema, a Delta Lake table is actually backed by a collection of files stored in cloud object storage.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC
-- MAGIC
-- MAGIC ## Explore Delta Lake Files
-- MAGIC
-- MAGIC We can see the files backing our Delta Lake table by using a Databricks Utilities function.
-- MAGIC
-- MAGIC **NOTE**: It's not important right now to know everything about these files to work with Delta Lake, but it will help you gain a greater appreciation for how the technology is implemented.

-- COMMAND ----------

-- MAGIC %python
-- MAGIC display(dbutils.fs.ls("s3://club-data-lakehouse-bucket/Datalakehouse/MDT/students"))

-- COMMAND ----------

-- MAGIC %md
-- MAGIC
-- MAGIC
-- MAGIC Note that our directory contains a number of Parquet data files and a directory named **`_delta_log`**.
-- MAGIC
-- MAGIC Records in Delta Lake tables are stored as data in Parquet files.
-- MAGIC
-- MAGIC Transactions to Delta Lake tables are recorded in the **`_delta_log`**.
-- MAGIC
-- MAGIC We can peek inside the **`_delta_log`** to see more.

-- COMMAND ----------

-- MAGIC %python
-- MAGIC display(dbutils.fs.ls("s3://club-data-lakehouse-bucket/Datalakehouse/MDT/students/_delta_log"))

-- COMMAND ----------

-- MAGIC %md
-- MAGIC
-- MAGIC
-- MAGIC Each transaction results in a new JSON file being written to the Delta Lake transaction log. Here, we can see that there are 8 total transactions against this table (Delta Lake is 0 indexed).

-- COMMAND ----------

-- MAGIC %md
-- MAGIC
-- MAGIC
-- MAGIC ## Reasoning about Data Files
-- MAGIC
-- MAGIC We just saw a lot of data files for what is obviously a very small table.
-- MAGIC
-- MAGIC **`DESCRIBE DETAIL`** allows us to see some other details about our Delta table, including the number of files.

-- COMMAND ----------

DESCRIBE DETAIL students

-- COMMAND ----------

-- MAGIC %md
-- MAGIC
-- MAGIC
-- MAGIC Here we see that our table currently contains 4 data files in its present version. So what are all those other Parquet files doing in our table directory? 
-- MAGIC
-- MAGIC Rather than overwriting or immediately deleting files containing changed data, Delta Lake uses the transaction log to indicate whether or not files are valid in a current version of the table.
-- MAGIC
-- MAGIC Here, we'll look at the transaction log corresponding the **`MERGE`** statement above, where records were inserted, updated, and deleted.

-- COMMAND ----------

-- MAGIC %python
-- MAGIC display(spark.sql(f"SELECT * FROM json.`s3://club-data-lakehouse-bucket/Datalakehouse/MDT/students/_delta_log/00000000000000000007.json`"))

-- COMMAND ----------

-- MAGIC %md
-- MAGIC
-- MAGIC
-- MAGIC The **`add`** column contains a list of all the new files written to our table; the **`remove`** column indicates those files that no longer should be included in our table.
-- MAGIC
-- MAGIC When we query a Delta Lake table, the query engine uses the transaction logs to resolve all the files that are valid in the current version, and ignores all other data files.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC
-- MAGIC
-- MAGIC ## Compacting Small Files
-- MAGIC
-- MAGIC Small files can occur for a variety of reasons; in our case, we performed a number of operations where only one or several records were inserted.
-- MAGIC
-- MAGIC Files will be combined toward an optimal size (scaled based on the size of the table) by using the **`OPTIMIZE`** command.
-- MAGIC
-- MAGIC **`OPTIMIZE`** will replace existing data files by combining records and rewriting the results.

-- COMMAND ----------

OPTIMIZE students

-- COMMAND ----------

-- MAGIC %md
-- MAGIC
-- MAGIC
-- MAGIC ## Reviewing Delta Lake Transactions
-- MAGIC
-- MAGIC Because all changes to the Delta Lake table are stored in the transaction log, we can easily review the <a href="https://docs.databricks.com/spark/2.x/spark-sql/language-manual/describe-history.html" target="_blank">table history</a>.

-- COMMAND ----------

DESCRIBE HISTORY students

-- COMMAND ----------

-- MAGIC %md
-- MAGIC
-- MAGIC
-- MAGIC As expected, **`OPTIMIZE`** created another version of our table, meaning that version 8 is our most current version.
-- MAGIC
-- MAGIC Remember all of those extra data files that had been marked as removed in our transaction log? These provide us with the ability to query previous versions of our table.
-- MAGIC
-- MAGIC These time travel queries can be performed by specifying either the integer version or a timestamp.
-- MAGIC
-- MAGIC **NOTE**: In most cases, you'll use a timestamp to recreate data at a time of interest. For our demo we'll use version, as this is deterministic (whereas you may be running this demo at any time in the future).

-- COMMAND ----------

SELECT * 
FROM students VERSION AS OF 3

-- COMMAND ----------

-- MAGIC %md
-- MAGIC
-- MAGIC
-- MAGIC What's important to note about time travel is that we're not recreating a previous state of the table by undoing transactions against our current version; rather, we're just querying all those data files that were indicated as valid as of the specified version.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC
-- MAGIC
-- MAGIC Delta Lake enables also to identify changes to the table in a selected period or table version range. This is helpful to identify delta changes and propagate to the other Data Lakehouse layers, enabling simple merge operations.

-- COMMAND ----------

SELECT * FROM table_changes('students', 0,10);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC
-- MAGIC
-- MAGIC ## Rollback Versions
-- MAGIC
-- MAGIC Suppose you're typing up query to manually delete some records from a table and you accidentally execute this query in the following state.

-- COMMAND ----------

DELETE FROM students

-- COMMAND ----------

-- MAGIC %md
-- MAGIC
-- MAGIC
-- MAGIC From the output above, we can see that 4 rows were removed.
-- MAGIC
-- MAGIC Let's confirm this below.

-- COMMAND ----------

SELECT * FROM students

-- COMMAND ----------

-- MAGIC %md
-- MAGIC
-- MAGIC
-- MAGIC Deleting all the records in your table is probably not a desired outcome. Luckily, we can simply rollback this commit.

-- COMMAND ----------

RESTORE TABLE students TO VERSION AS OF 8

-- COMMAND ----------

-- MAGIC %md
-- MAGIC
-- MAGIC
-- MAGIC Note that a **`RESTORE`** <a href="https://docs.databricks.com/spark/latest/spark-sql/language-manual/delta-restore.html" target="_blank">command</a> is recorded as a transaction; you won't be able to completely hide the fact that you accidentally deleted all the records in the table, but you will be able to undo the operation and bring your table back to a desired state.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC
-- MAGIC  
-- MAGIC Run the following cell to delete the tables and files associated with this lesson.

-- COMMAND ----------

DROP TABLE students;

-- COMMAND ----------

-- MAGIC %python
-- MAGIC dbutils.fs.rm('s3://club-data-lakehouse-bucket/Datalakehouse/MDT/students', recurse=True)
