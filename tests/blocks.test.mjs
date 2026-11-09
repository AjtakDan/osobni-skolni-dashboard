import assert from 'node:assert/strict';import {scheduleForDate,lessonStatus,splitLessonBlocks} from '../web/core.js';
const rows=[{id:'double',subject:'s',date:'2026-11-12',day:4,start:'08:30',end:'10:05',room:'A',period:1}];
const split=scheduleForDate(rows,'2026-11-12');assert.equal(split.length,2);assert.deepEqual(split.map(l=>[l.start,l.end]),[['08:30','09:15'],['09:20','10:05']]);assert.equal(split[1].period,2);
assert.equal(lessonStatus(rows,new Date('2026-11-12T08:16:00Z')).phase,'break');
const cancelled=scheduleForDate(rows,'2026-11-12',[{id:'cancel',date:'2026-11-12',start:'08:30',end:'10:05',action:'cancelled'}]);assert.equal(cancelled.length,2);assert.ok(cancelled.every(l=>l.cancelled));
assert.equal(splitLessonBlocks([{...rows[0],start:'09:00',end:'10:00'}]).length,1);console.log('PASS double lessons: two periods, actual break, cancellation preserved, unknown boundaries unchanged');
