#!/bin/bash

# Check for correct number of arguments
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 input.csv output.csv numeric_columns"
    echo "Example: $0 data.csv cleaned_data.csv 2,3"
    exit 1
fi

INPUT_CSV="$1"
OUTPUT_CSV="$2"
NUMERIC_COLUMNS="$3"
REPORT_FILE="cleaning_report.txt"

# Check if input file exists
if [ ! -f "$INPUT_CSV" ]; then
    echo "Error: Input file $INPUT_CSV does not exist"
    exit 1
fi

# Initialize report
echo "Cleaning Report for $INPUT_CSV" > "$REPORT_FILE"
echo "Date: $(date)" >> "$REPORT_FILE"
echo "----------------------------------------" >> "$REPORT_FILE"

# Step 1: Count total rows
TOTAL_ROWS=$(wc -l < "$INPUT_CSV")
echo "Total rows: $TOTAL_ROWS" >> "$REPORT_FILE"

# Step 2: Check for missing values and impute (mean for numeric, 'unknown' for text)
MISSING_COUNT=0
awk -F',' -v OFS=',' '
BEGIN { print "Processing missing values..." > "/dev/stderr" }
NR==1 { header=$0; print; next }
{
    missing=0
    for (i=1; i<=NF; i++) {
        if ($i == "" || $i ~ /^[ \t]*$/) {
            missing++
            if (i in numeric_cols) {
                $i = "NA"  # Mark for mean imputation later
            } else {
                $i = "unknown"
            }
        }
    }
    if (missing > 0) {
        print "Row " NR " has " missing " missing values" > "'"$REPORT_FILE"'"
    }
    print
}
' "$INPUT_CSV" > temp.csv

echo "Missing values found: $MISSING_COUNT" >> "$REPORT_FILE"

# Step 3: Impute mean for numeric columns
IFS=',' read -ra NUM_COLS <<< "$NUMERIC_COLUMNS"
for COL in "${NUM_COLS[@]}"; do
    # Calculate mean for non-empty, numeric values in the column
    MEAN=$(awk -F',' -v col="$COL" '
    NR>1 && $col !~ /^[ \t]*$/ && $col != "NA" && $col ~ /^[0-9]+(\.[0-9]+)?$/ { sum+=$col; count++ }
    END { if (count > 0) print sum/count; else print 0 }
    ' temp.csv)
    echo "Mean for column $COL: $MEAN" >> "$REPORT_FILE"
    
    # Replace NA with mean in numeric column
    awk -F',' -v OFS=',' -v col="$COL" -v mean="$MEAN" '
    NR==1 { print; next }
    $col == "NA" { $col = mean }
    { print }
    ' temp.csv > temp2.csv
    mv temp2.csv temp.csv
done

# Step 4: Remove duplicates
DUPLICATES=$(awk -F',' 'NR>1 { lines[$0]++ } END { for (line in lines) if (lines[line] > 1) print line }' temp.csv | wc -l)
awk -F',' '!seen[$0]++' temp.csv > "$OUTPUT_CSV"
echo "Duplicate rows removed: $DUPLICATES" >> "$REPORT_FILE"

# Step 5: Validate numeric columns
for COL in "${NUM_COLS[@]}"; do
    NON_NUMERIC=$(awk -F',' -v col="$COL" 'NR>1 && $col !~ /^[0-9]+(\.[0-9]+)?$/ && $col !~ /^[ \t]*$/ { print $col }' "$OUTPUT_CSV" | wc -l)
    if [ "$NON_NUMERIC" -gt 0 ]; then
        echo "Warning: Column $COL contains $NON_NUMERIC non-numeric values" >> "$REPORT_FILE"
    fi
done

# Step 6: Clean up
rm temp.csv
FINAL_ROWS=$(wc -l < "$OUTPUT_CSV")
echo "Final row count: $FINAL_ROWS" >> "$REPORT_FILE"
echo "Cleaning completed. Output written to $OUTPUT_CSV" >> "$REPORT_FILE"
echo "Report generated at $REPORT_FILE"
