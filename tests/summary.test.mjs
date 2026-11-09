import assert from 'node:assert/strict';import {gradeSummary} from '../web/core.js';
assert.equal(gradeSummary([{assessmentType:'points',score:10,maxPoints:20},{assessmentType:'points',score:20,maxPoints:20}]).value,75);
assert.equal(gradeSummary([{assessmentType:'percent',score:40,maxPoints:50,weight:2},{assessmentType:'percent',score:50,maxPoints:100,weight:1}]).value,70);
assert.equal(gradeSummary([{assessmentType:'points',score:1}]),null);assert.equal(gradeSummary([]),null);console.log('PASS point and percentage summaries, incomplete data rejected');
const {estimatedGrade}=await import('../web/core.js');for(const [value,grade]of [[100,1],[90,1],[89.999,2],[75,2],[74.99,3],[60,3],[59.99,4],[45,4],[44.99,5],[0,5]])assert.equal(estimatedGrade(value),grade);assert.equal(estimatedGrade(null),null);console.log('PASS estimated grade at every exact boundary');
