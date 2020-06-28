package org.fitrecord.android.service

import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.AsyncTask
import android.os.Binder
import android.os.Handler
import android.os.IBinder
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

open class ConnectableServiceConnection<T : ConnectableService>() : ServiceConnection {

    private var service: T? = null
    private val lock = ReentrantLock()
    private val cond = lock.newCondition()

    override fun onServiceDisconnected(name: ComponentName?) {
        service?.let {
            onDisconnected(it)
            service = null
        }
    }

    override fun onServiceConnected(name: ComponentName?, svc: IBinder?) {
        service = (svc as ConnectableService.ConnectableServiceBinder<T>).getService().apply {
            lock.withLock {
                cond.signalAll()
            }
            onConnected(this)
        }
    }

    fun <R> with(callback: (service: T) -> R): R {
        lock.withLock {
            if (service == null)
                cond.await()
            return callback(service!!)
        }
    }

    fun post(callback: (service: T) -> Unit?) {
        with { it.mainHandler.post { callback(it) } }
    }

    fun async(lambda: (service: T) -> Unit?) {
        object : AsyncTask<Unit?, Nothing, Unit?>() {
            override fun doInBackground(vararg p: Unit?): Unit? {
                return with {
                    lambda(it)
                }
            }
        }.execute(null)
    }

    fun bind(context: Context, cls: Class<T>) {
        val intent = Intent(context, cls)
        context.bindService(intent, this, Context.BIND_AUTO_CREATE)
    }

    fun start(context: Context, cls: Class<T>) {
        val intent = Intent(context, cls)
        context.startService(intent)
    }

    fun unbind(context: Context) {
        service.let {
            context.unbindService(this)
        }
    }

    open fun onConnected(service: T) {}
    open fun onDisconnected(service: T) {}

}

abstract class ConnectableService : Service() {

    inner class ConnectableServiceBinder<T : ConnectableService> : Binder() {

        fun getService(): T {
            return this@ConnectableService as T
        }
    }

    private val localBinder = ConnectableServiceBinder<ConnectableService>()
    internal lateinit var mainHandler: Handler

    override fun onCreate() {
        super.onCreate()
        mainHandler = Handler(mainLooper)
    }

    override fun onBind(intent: Intent?): IBinder? {
        return localBinder
    }

}
