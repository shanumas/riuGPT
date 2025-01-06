from application.retriever.base import BaseRetriever
from application.core.settings import settings
from application.vectorstore.vector_creator import VectorCreator
from application.llm.llm_creator import LLMCreator

from application.utils import num_tokens_from_string


class ClassicRAG(BaseRetriever):

    def __init__(
        self,
        question,
        source,
        chat_history=None,
        prompt="",
        chunks=3,
        token_limit=150,
        gpt_model="docsgpt",
        user_api_key=None,
    ):
        self.question = question
        self.primary_vectorstore = source.get('active_docs', None)
        self.additional_vectorstore = source.get('guide_docs', None)
        self.chat_history = chat_history if chat_history else []
        self.prompt = prompt
        self.chunks = chunks
        self.gpt_model = gpt_model
        self.token_limit = (
            token_limit
            if token_limit
            < settings.MODEL_TOKEN_LIMITS.get(
                self.gpt_model, settings.DEFAULT_MAX_HISTORY
            )
            else settings.MODEL_TOKEN_LIMITS.get(
                self.gpt_model, settings.DEFAULT_MAX_HISTORY
            )
        )
        self.user_api_key = user_api_key        

    def _get_data_from_vectorstore(self, vectorstore, k):
        if k == 0 or not vectorstore:
            return []
        docsearch = VectorCreator.create_vectorstore(
            settings.VECTOR_STORE, vectorstore, settings.EMBEDDINGS_KEY
        )
        docs_temp = docsearch.search(self.question, k=k)
        docs = [
            {
                "title": i.metadata.get(
                    "title", i.metadata.get("post_title", i.page_content)
                ).split("/")[-1],
                "text": i.page_content,
                "source": i.metadata.get("source", "local"),
            }
            for i in docs_temp
        ]
        return docs

    def _retrieve_guidelines(self):
        """
        Retrieve the exact guidelines from the additional vector store.
        """
        if not self.additional_vectorstore:
            print("Additional vector store not initialized.")
            return ""

        guidelines_docs = self._get_data_from_vectorstore(self.additional_vectorstore, k=2)

        if not guidelines_docs:
            print("No guidelines found in the additional vector store.")
            return ""

        guidelines_text = "\n".join(doc["text"] for doc in guidelines_docs)
        return guidelines_text

    def _summarize_guidelines(self, guidelines_text):
        """
        First LLM call: Summarize the guidelines_text.
        This ensures that all guideline-related info is prepared before checking primary docs.
        """
        if not guidelines_text.strip():
            return "No guidelines available."

        # Prompt for summarizing guidelines
        summary_prompt = (
            "You are an assistant that reads sustainability/ESG reporting guidelines.\n"
            "Please summarize the key points related to emissions reporting found in the provided guidelines.\n\n"
            "GUIDELINES:\n" + guidelines_text
        )

        llm = LLMCreator.create_llm(
            settings.LLM_NAME, api_key=settings.API_KEY, user_api_key=self.user_api_key
        )
        summary = llm.gen(model=self.gpt_model, messages=[{"role":"system","content":summary_prompt}])
        return summary.strip()

    def _retrieve_primary_docs(self):
        """
        Retrieve documents from the primary vector store related to the user's question.
        """
        if not self.primary_vectorstore:
            print("Primary vector store not initialized.")
            return []
        primary_docs = self._get_data_from_vectorstore(self.primary_vectorstore, self.chunks)
        return primary_docs

    def gen(self):
        # Step 1: Retrieve guidelines
        guidelines_text = self._retrieve_guidelines()

        # Step 2: Summarize the guidelines with the first LLM call
        summarized_guidelines = self._summarize_guidelines(guidelines_text)

        # Step 3: Retrieve primary documents
        primary_docs = self._retrieve_primary_docs()

        # Combine summarized guidelines and primary docs
        # We now have a prepared guidelines summary and the primary data
        docs = primary_docs.copy()
        if summarized_guidelines:
            docs.append({
                "title": "Summarized_Guidelines",
                "text": summarized_guidelines,
                "source": "guidelines_summary"
            })

        # Yield sources before the second call
        for doc in docs:
            yield {"source": doc}

        # Step 4: Prepare the second LLM call
        # Join all docs
        docs_together = "\n".join([f"Title: {doc['title']}\nText: {doc['text']}" for doc in docs])

        # System prompt for second call: instruct the LLM to use summarized guidelines + primary docs
        system_prompt = (
            "You are a system that uses the summarized guidelines and the retrieved primary documents to answer the user's question.\n"
            "Only use the 'Summarized_Guidelines' doc as the source for any guideline-related information.\n"
            "Do not invent guidelines not present in 'Summarized_Guidelines'.\n\n"
            "Never mention any document names:\n"
            "Below are the documents you have access to:\n"
            "{summaries}"
        )

        p_chat_combine = system_prompt.replace("{summaries}", docs_together)

        messages_combine = [
            {"role": "system", "content": p_chat_combine},
            {"role": "user", "content": self.question + "\n\nUse the primary documents to determine actual emissions data if available."}
        ]

        # Add chat history if needed
        if len(self.chat_history) > 1:
            tokens_current_history = 0
            for i in self.chat_history:
                if "prompt" in i and "response" in i:
                    tokens_batch = num_tokens_from_string(i["prompt"]) + num_tokens_from_string(i["response"])
                    if tokens_current_history + tokens_batch < self.token_limit:
                        tokens_current_history += tokens_batch
                        messages_combine.append({"role": "user", "content": i["prompt"]})
                        messages_combine.append({"role": "system", "content": i["response"]})

        # Step 5: Final LLM call for the answer
        llm = LLMCreator.create_llm(
            settings.LLM_NAME, api_key=settings.API_KEY, user_api_key=self.user_api_key
        )
        completion = llm.gen_stream(model=self.gpt_model, messages=messages_combine)
        for line in completion:
            yield {"answer": str(line)}

    def search(self):
        # Returns combined data for debugging or other purposes
        guidelines_text = self._retrieve_guidelines()
        primary_docs = self._retrieve_primary_docs()
        combined_docs = primary_docs.copy()
        if guidelines_text:
            combined_docs.append({
                "title": "Guidelines_doc",
                "text": guidelines_text,
                "source": "guidelines"
            })
        return combined_docs
    
    def get_params(self):
        return {
            "question": self.question,
            "source": self.primary_vectorstore,
            "chat_history": self.chat_history,
            "prompt": self.prompt,
            "chunks": self.chunks,
            "token_limit": self.token_limit,
            "gpt_model": self.gpt_model,
            "user_api_key": self.user_api_key
        }
