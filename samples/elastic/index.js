/**
 * Author : SungYong Jang, jsy@adain.kr
 * Date :  2022/11/21
 * Description :
 */

const { Client } = require('@elastic/elasticsearch');
const client = new Client({
  node: 'http://localhost:9200'
});

async function run(){
  await client.index({
    index: 'my_index_1',
    body: {
      temp: Math.floor(Math.random() * 100),
      timestamp: Date.now(),
    }
  });
}

run().catch((e)=>{
  console.log(e);
});