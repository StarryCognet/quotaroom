package com.starrycognet.quotaroom

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Compact quota widget. All values are formatted by Dart (WidgetService) and
 * stored through home_widget; this provider only binds them.
 */
class QuotaRoomWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.quotaroom_widget)
            views.setTextViewText(
                R.id.widget_account,
                widgetData.getString("qr_account", "QuotaRoom") ?: "QuotaRoom",
            )
            views.setTextViewText(
                R.id.widget_updated,
                widgetData.getString("qr_updated", "") ?: "",
            )
            bindQuota(views, widgetData, 1)
            bindQuota(views, widgetData, 2)
            bindQuota(views, widgetData, 3)
            views.setTextViewText(
                R.id.qr_today_label,
                widgetData.getString("qr_today_label", "今日") ?: "今日",
            )
            views.setTextViewText(
                R.id.qr_today_cost,
                widgetData.getString("qr_today_cost", "—") ?: "—",
            )
            views.setTextViewText(
                R.id.qr_today_tokens,
                widgetData.getString("qr_today_tokens", "—") ?: "—",
            )
            views.setTextViewText(
                R.id.qr_today_meta,
                widgetData.getString("qr_today_meta", "") ?: "",
            )
            views.setOnClickPendingIntent(
                R.id.widget_container,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun bindQuota(
        views: RemoteViews,
        data: SharedPreferences,
        slot: Int,
    ) {
        views.setTextViewText(
            when (slot) {
                1 -> R.id.widget_q1_label
                2 -> R.id.widget_q2_label
                else -> R.id.widget_q3_label
            },
            data.getString("qr_q${slot}_label", "—") ?: "—",
        )
        views.setTextViewText(
            when (slot) {
                1 -> R.id.widget_q1_pct
                2 -> R.id.widget_q2_pct
                else -> R.id.widget_q3_pct
            },
            data.getString("qr_q${slot}_pct", "--") ?: "--",
        )
        views.setProgressBar(
            when (slot) {
                1 -> R.id.widget_q1_bar
                2 -> R.id.widget_q2_bar
                else -> R.id.widget_q3_bar
            },
            100,
            data.getInt("qr_q${slot}_progress", 0),
            false,
        )
    }
}
