/*
  PROJECT: Supply Chain Analytics
  DDI: Weekly Inventory Projection Model
  DIALECT: Snowflake SQL
  AUTHOR: aleksbil
  
  DESCRIPTION: 
  This script calculates a recursive week-over-week stock projection 
  considering production shifts, transport minimums, and demand scenarios (SO vs FCST).
*/

-- Base dataset: weekly supply planning data
with base as (
    select 
        item_id,
        location_id,
        item_key,
        to_date(week_date, 'YYYY.MM.DD') as week_date,

        ifnull(adjusted_receipts,0) as adjusted_receipts,
        ifnull(target_inventory,0) as target_inventory,
        ifnull(forecast_demand,0) as forecast_demand,
        ifnull(open_orders,0) as open_orders,
        ifnull(min_transport,0) as min_transport,
        ifnull(min_external,0) as min_external,

        case 
            when location_id = 'A' 
                then ifnull(production_receipts,0)
            else ifnull(shifted_production_receipts,0)
        end as production_shifted,

        ifnull(stock_on_hand,0) as stock_on_hand
    from SUPPLY_WEEKLY_DATA
    left join SUPPLY_WEEKLY_DATA shifted
        on item_id = shifted.item_id
        and shifted.location_id = 'A'
        and to_date(week_date, 'YYYY.MM.DD') 
            = to_date(shifted.week_date, 'YYYY.MM.DD') + interval '7 day'
    where
        to_date(week_date, 'YYYY.MM.DD') >= date_trunc('week', current_date)
),

-- Recursive weekly stock calculation
recursive_stock as (
    select
        item_id,
        location_id,
        item_key,
        week_date,
        adjusted_receipts,
        target_inventory,
        forecast_demand,
        open_orders,
        min_transport,
        min_external,
        production_shifted,
        stock_on_hand,
        stock_on_hand as stock_oh_so,
        stock_on_hand as stock_oh_fcst
    from base
    where week_date = (select min(week_date) from base)

    union all

    select
        b.item_id,
        b.location_id,
        b.item_key,
        b.week_date,
        b.adjusted_receipts,
        b.target_inventory,
        b.forecast_demand,
        b.open_orders,
        b.min_transport,
        b.min_external,
        b.production_shifted,
        b.stock_on_hand,

        r.stock_oh_so
            + r.production_shifted
            + r.min_transport
            + r.min_external
            - r.open_orders
            as stock_oh_so,

        r.stock_oh_fcst
            + r.production_shifted
            + r.min_transport
            + r.min_external
            - r.open_orders
            - r.forecast_demand
            as stock_oh_fcst

    from base b
    join recursive_stock r
        on b.item_id = r.item_id
        and b.location_id = r.location_id
        and b.week_date = r.week_date + interval '7 day'
),

-- Join with item master data
final as (
    select
        rs.*,
        md.item_description,
        md.hierarchy_level_1,
        md.hierarchy_level_2,
        md.hierarchy_level_3
    from recursive_stock rs
    left join ITEM_MASTER md
        on rs.item_key = md.item_key
)

-- Final projection output
select
    item_id as "Item",
    location_id as "Location",
    week_date as "Week",

    item_description as "Item Description",
    hierarchy_level_1 as "Hierarchy L1",
    hierarchy_level_2 as "Hierarchy L2",
    hierarchy_level_3 as "Hierarchy L3",

    adjusted_receipts as "Adjusted Receipts",
    target_inventory as "Target Inventory",
    forecast_demand as "Forecast Demand",
    open_orders as "Open Orders",
    min_transport as "Min Transport",
    min_external as "Min External",
    production_shifted as "Shifted Production",
    stock_on_hand as "Stock On Hand",
    stock_oh_so as "Stock OH (SO)",
    stock_oh_fcst as "Stock OH (FCST)",

    stock_oh_so
        + production_shifted
        + min_transport
        + min_external
        - open_orders
        as "Projected Stock (SO)",

    stock_oh_fcst
        + production_shifted
        + min_transport
        + min_external
        - open_orders
        - forecast_demand
        as "Projected Stock (FCST)"

from final
order by week_date, location_id;
