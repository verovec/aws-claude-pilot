locals {
  service = "monitoring"
  prefix  = "${var.project}-${var.environment}"

  tags = merge(var.common_tags, {
    Service = local.service
  })

  categories      = distinct([for s in var.ecs_services : s.category])
  services_by_cat = { for cat in local.categories : cat => { for k, s in var.ecs_services : k => s if s.category == cat } }
  category_labels = { "api" = "API", "worker" = "Worker", "scheduler" = "Scheduler" }

  widget_height = 6

  cat_count      = max(length(local.categories), 1)
  cat_base_width = (24 - (24 % local.cat_count)) / local.cat_count
  cat_remainder  = 24 % local.cat_count
  cat_widths     = [for i in range(local.cat_count) : i < local.cat_remainder ? local.cat_base_width + 1 : local.cat_base_width]
  cat_positions  = [for i in range(local.cat_count) : i == 0 ? 0 : sum([for j in range(i) : local.cat_widths[j]])]

  ecs_cpu_widgets = [for idx, cat in local.categories : {
    type   = "metric"
    x      = local.cat_positions[idx]
    y      = 0
    width  = local.cat_widths[idx]
    height = local.widget_height
    properties = {
      title   = "${lookup(local.category_labels, cat, title(cat))} CPU Utilization"
      view    = "timeSeries"
      stacked = false
      region  = var.aws_region
      period  = 300
      stat    = "Average"
      metrics = [for k, s in local.services_by_cat[cat] : [
        "AWS/ECS", "CPUUtilization",
        "ClusterName", var.ecs_cluster_name,
        "ServiceName", s.service_name,
        { label = k }
      ]]
    }
  }]

  ecs_memory_widgets = [for idx, cat in local.categories : {
    type   = "metric"
    x      = local.cat_positions[idx]
    y      = local.widget_height
    width  = local.cat_widths[idx]
    height = local.widget_height
    properties = {
      title   = "${lookup(local.category_labels, cat, title(cat))} Memory Utilization"
      view    = "timeSeries"
      stacked = false
      region  = var.aws_region
      period  = 300
      stat    = "Average"
      metrics = [for k, s in local.services_by_cat[cat] : [
        "AWS/ECS", "MemoryUtilization",
        "ClusterName", var.ecs_cluster_name,
        "ServiceName", s.service_name,
        { label = k }
      ]]
    }
  }]

  ecs_y_end = local.widget_height * 2

  has_rds         = length(var.rds_instances) > 0
  rds_y           = local.ecs_y_end
  rds_metric_list = local.has_rds ? [
    { key = "CPUUtilization", title = "RDS CPU Utilization" },
    { key = "FreeStorageSpace", title = "RDS Free Storage" },
    { key = "DatabaseConnections", title = "RDS Connections" },
    { key = "ReadLatency", title = "RDS Read Latency" },
    { key = "WriteLatency", title = "RDS Write Latency" },
  ] : []
  rds_count      = length(local.rds_metric_list)
  rds_base_width = local.rds_count > 0 ? (24 - (24 % local.rds_count)) / local.rds_count : 0
  rds_remainder  = local.rds_count > 0 ? 24 % local.rds_count : 0
  rds_widths     = [for i in range(local.rds_count) : i < local.rds_remainder ? local.rds_base_width + 1 : local.rds_base_width]
  rds_positions  = [for i in range(local.rds_count) : i == 0 ? 0 : sum([for j in range(i) : local.rds_widths[j]])]

  rds_widgets = [for idx, m in local.rds_metric_list : {
    type   = "metric"
    x      = local.rds_positions[idx]
    y      = local.rds_y
    width  = local.rds_widths[idx]
    height = local.widget_height
    properties = {
      title   = m.title
      view    = "timeSeries"
      stacked = false
      region  = var.aws_region
      period  = 300
      stat    = "Average"
      metrics = [for label, id in var.rds_instances : [
        "AWS/RDS", m.key,
        "DBInstanceIdentifier", id,
        { label = label }
      ]]
    }
  }]

  rds_y_end = local.has_rds ? local.rds_y + local.widget_height : local.ecs_y_end

  log_stream_filters = {
    for cat in local.categories : cat => join("|", [for k, s in local.services_by_cat[cat] : s.service_name])
  }

  log_height = 8

  log_widgets = [for idx, cat in local.categories : {
    type   = "log"
    x      = 0
    y      = local.rds_y_end + (idx * local.log_height)
    width  = 24
    height = local.log_height
    properties = {
      title  = "${lookup(local.category_labels, cat, title(cat))} Logs"
      region = var.aws_region
      query  = "SOURCE '${var.log_group_name}' | filter @logStream like /${local.log_stream_filters[cat]}/ | fields @timestamp, @message | sort @timestamp desc | limit 200"
      view   = "table"
    }
  }]

  all_widgets = concat(
    local.ecs_cpu_widgets,
    local.ecs_memory_widgets,
    local.rds_widgets,
    local.log_widgets,
  )
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.prefix}-${var.application_name}"
  dashboard_body = jsonencode({ widgets = local.all_widgets })
}
