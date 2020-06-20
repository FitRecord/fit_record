package org.fitrecord.android.service

class Listeners<T> {
    private val listeners = ArrayList<T>()
    
    fun add(listener: T) {
        synchronized(listeners) {
            if (!listeners.contains(listener)) {
                listeners.add(listener)
            }
        }
    }

    fun remove(listener: T) {
        synchronized(listeners) {
            listeners.remove(listener)
        }
    }
    
    fun invoke(callback: (listener: T) -> Unit) {
        synchronized(listeners) {
            listeners.forEach { 
                callback(it)
            }
        }
    }
}