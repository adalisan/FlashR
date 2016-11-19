#ifndef __CONCURRENCY_H__
#define __CONCURRENCY_H__

/*
 * Copyright 2014 Open Connectome Project (http://openconnecto.me)
 * Written by Da Zheng (zhengda1936@gmail.com)
 *
 * This file is part of SAFSlib.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <pthread.h>

template<class T>
class atomic_number
{
	volatile T v;
public:
	atomic_number() {
		v = 0;
	}

	atomic_number(T init) {
		v = init;
	}

	T inc(T by) {
		return __sync_add_and_fetch(&v, by);
	}

	T dec(T by) {
		return __sync_sub_and_fetch(&v, by);
	}

	T get() const {
		return v;
	}

	bool CAS(T expected, T value) {
		return __sync_bool_compare_and_swap(&v, expected, value);
	}
};

class atomic_unsigned_integer: public atomic_number<unsigned int>
{
public:
	atomic_unsigned_integer() {
	}

	atomic_unsigned_integer(unsigned int init): atomic_number<unsigned int>(
			init) {
	}
};

class atomic_integer: public atomic_number<int>
{
public:
	atomic_integer() {
	}

	atomic_integer(int init): atomic_number<int>(init) {
	}
};

class atomic_long: public atomic_number<long>
{
public:
	atomic_long() {
	}

	atomic_long(long init): atomic_number<long>(init) {
	}
};

class seq_lock
{
	volatile unsigned long count;
	pthread_spinlock_t lock;
public:
	seq_lock() {
		count = 0;
		pthread_spin_init(&lock, PTHREAD_PROCESS_PRIVATE);
	}

	~seq_lock() {
		pthread_spin_destroy(&lock);
	}

	void read_lock(unsigned long &count) const {
		/*
		 * If the count is odd, it means another thread is changing
		 * the data structure the lock tries to protect. 
		 */
		do {
			count = this->count;
		} while (count & 1);
	}

	bool read_unlock(unsigned long count) const {
		return this->count == count;
	}

	void write_lock() {
		pthread_spin_lock(&lock);
		__sync_fetch_and_add(&count, 1);
	}

	void write_unlock() {
		__sync_fetch_and_add(&count, 1);
		pthread_spin_unlock(&lock);
	}
};

template<class T>
class atomic_flags
{
	volatile T flags;
public:
	atomic_flags() {
		flags = 0;
	}

	/*
	 * Set the flag and return the orig flag.
	 */
	bool set_flag(int flag) {
		int orig = __sync_fetch_and_or(&flags, 0x1 << flag);
		return orig & (0x1 << flag);
	}

	/*
	 * Clear the flag and return the orig flag.
	 */
	bool clear_flag(int flag) {
		int orig = __sync_fetch_and_and(&flags, ~(0x1 << flag));
		return orig & (0x1 << flag);
	}

	bool test_flag(int flag) const {
		return flags & (0x1 << flag);
	}

	int get_num_tot_flags() const {
		return sizeof(T) * 8;
	}
};

class spin_lock
{
	pthread_spinlock_t _lock;
public:
	spin_lock() {
		pthread_spin_init(&_lock, PTHREAD_PROCESS_PRIVATE);
	}

	void lock() {
		pthread_spin_lock(&_lock);
	}

	void unlock() {
		pthread_spin_unlock(&_lock);
	}
};

#endif
